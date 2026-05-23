import Foundation
import PixelCore

public struct CLIBackend: ChatBackend {
    public let kind: CLIKind
    public let modelID: String
    public let executablePath: String

    public init(kind: CLIKind, executablePath: String, modelID: String? = nil) {
        self.kind = kind
        self.executablePath = executablePath
        self.modelID = modelID ?? Self.defaultModelID(for: kind)
    }

    public init(kind: CLIKind, detector: CLIDetector = CLIDetector()) throws {
        guard let path = detector.locate(kind) else {
            throw BackendError.cliNotFound(name: kind.executableName)
        }
        self.init(kind: kind, executablePath: path)
    }

    /// Her CLI için varsayılan model ID. Öncelik sırası (v0.2.22):
    /// 1. **UserDefaults** (`pixel.model.<kind>`) — UI picker yazıyor; en yüksek öncelik.
    /// 2. **Env var** (`PIXEL_CLAUDE_MODEL` / `PIXEL_CODEX_MODEL` / `PIXEL_GEMINI_MODEL`).
    /// 3. **Hardcoded fallback** (23 May 2026):
    ///    - Claude: `claude-opus-4-7`
    ///    - Codex: `gpt-5.5`
    ///    - Gemini: `gemini-2.5-flash` (3.5 Flash henüz Google API'de yok, v0.2.21'de doğrulandı)
    ///
    /// Caller `CLIBackend.init(..., modelID:)` ile her zaman explicit override edebilir
    /// (bu fonksiyon çağrılmaz). UI/env katmanı default'u set ediyorsa burası seçer.
    public static func defaultModelID(for kind: CLIKind) -> String {
        // 1. UserDefaults (UI model picker)
        if let stored = UserDefaults.standard.string(forKey: ModelCatalog.userDefaultsKey(for: kind)),
           !stored.trimmingCharacters(in: .whitespaces).isEmpty {
            return stored
        }

        // 2. Env var
        let envKey: String
        let hardcoded: String
        switch kind {
        case .claude:
            envKey = "PIXEL_CLAUDE_MODEL"
            hardcoded = "claude-opus-4-7"
        case .codex:
            envKey = "PIXEL_CODEX_MODEL"
            hardcoded = "gpt-5.5"
        case .gemini:
            envKey = "PIXEL_GEMINI_MODEL"
            // Kullanıcı tercihi: 3.5 Flash (v0.2.23). v0.2.21'de CLI'nin tanıdığı
            // sürümde yoktu; ilerlemiş bir CLI sürümünde mevcut olabilir. Catalog'da
            // 2.5/2.0/1.5 family yedek olarak var — picker'dan seçilebilir.
            hardcoded = "gemini-3.5-flash"
        }
        if let override = ProcessInfo.processInfo.environment[envKey],
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }

        // 3. Hardcoded
        return hardcoded
    }

    public func send(
        messages: [Message],
        system: String?,
        options: ChatOptions
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        let prompt = Self.composedPrompt(messages: messages, system: system)
        let kind = self.kind
        let executablePath = self.executablePath

        let modelID = self.modelID
        return AsyncThrowingStream { continuation in
            let task = Task {
                let stdin: String? = Self.usesStdinForPrompt(for: kind) ? prompt : nil
                // **v0.2.17 fix:** Launchpad'den açıldığında PATH minimal —
                // Gemini CLI'ın `#!/usr/bin/env node` shebang'ı node'u bulamaz.
                // EnvironmentBuilder bilinen lokasyonları PATH'e prepend eder.
                //
                // **v0.2.21 fix:** Launchpad cwd `/` — Gemini CLI uyarı veriyor
                // ve tüm filesystem'i context'e alıyor. App Support altında
                // dedicated boş workspace cwd olarak set edilir.
                let runner = CLIProcessRunner(
                    executablePath: executablePath,
                    arguments: Self.arguments(for: kind, prompt: prompt, options: options, modelID: modelID),
                    environment: EnvironmentBuilder.augmentedEnvironment(),
                    workingDirectory: EnvironmentBuilder.resolveCLIWorkspaceDirectory()
                )
                let mode = Self.outputMode(for: kind)

                do {
                    var emittedAny = false
                    for try await line in runner.runStreamingLines(stdin: stdin) {
                        if Task.isCancelled { break }

                        switch mode {
                        case .streamJSON:
                            guard let delta = StreamJSONParser.parse(line) else { continue }
                            continuation.yield(delta)
                            if case .done = delta {
                                continuation.finish()
                                return
                            }
                        case .codexJSON:
                            guard let delta = CodexJSONParser.parse(line) else { continue }
                            continuation.yield(delta)
                            if case .done = delta {
                                continuation.finish()
                                return
                            }
                        case .text:
                            continuation.yield(.textChunk(emittedAny ? "\n\(line)" : line))
                            emittedAny = true
                        }
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public enum OutputMode {
        case streamJSON
        case codexJSON
        case text
    }

    public static func outputMode(for kind: CLIKind) -> OutputMode {
        switch kind {
        case .claude: return .streamJSON
        case .codex: return .codexJSON
        case .gemini: return .text
        }
    }

    /// Bu CLI gerçek token-by-token streaming için yapılandırılmış mı?
    /// Claude `--output-format stream-json` partial token verir. Codex
    /// `item.completed` ile tam yanıt verir (block). Gemini text mode (block).
    public static func usesStreamJSON(for kind: CLIKind) -> Bool {
        kind == .claude
    }

    public static func usesStdinForPrompt(for kind: CLIKind) -> Bool {
        kind == .codex
    }

    /// CLI binary'sine geçilecek argümanlar. `internal` yapıldı ki testler doğrulayabilsin.
    ///
    /// **v0.2.19:** Her CLI için `--model <modelID>` flag'i prepend edilir
    /// (Claude/Codex/Gemini hepsi long-form `--model`'i destekliyor).
    static func arguments(
        for kind: CLIKind,
        prompt: String,
        options: ChatOptions,
        modelID: String
    ) -> [String] {
        switch kind {
        case .claude:
            var args = [
                "--model", modelID,
                "-p",
                "--output-format", "stream-json",
                "--include-partial-messages",
                "--verbose",
            ]
            if options.planMode {
                // Claude CLI Plan Mode: read-only tool allowlist (Read/Glob/Grep aktif,
                // Edit/Write/Bash devre dışı). Spec: docs.anthropic.com/claude/cli
                args.append(contentsOf: ["--permission-mode", "plan"])
            }
            args.append(prompt)
            return args
        case .codex:
            // Codex `exec` subcommand + stdin (dash); prompt arg değil.
            // Plan Mode native değil — bayrak yok, normal akışa devam.
            return [
                "exec",
                "--model", modelID,
                "--json",
                "--ignore-user-config",
                "--skip-git-repo-check",
                "--dangerously-bypass-approvals-and-sandbox",
                "-",
            ]
        case .gemini:
            // Gemini CLI Plan Mode'a native destek vermiyor — bayrak yok.
            // `--skip-trust`: Headless/automated context (pixel-agent spawn'ı)
            // için trusted-workspace promptunu atla. v0.2.17+ ek olarak
            // EnvironmentBuilder GEMINI_CLI_TRUST_WORKSPACE=true set ediyor —
            // belt & suspenders (eski Gemini CLI sürümleri flag, yeni'ler env
            // var bekliyor olabilir).
            return ["--model", modelID, "--skip-trust", "-p", prompt]
        }
    }

    private static func composedPrompt(messages: [Message], system: String?) -> String {
        var parts: [String] = []
        if let system, !system.isEmpty {
            parts.append("System: \(system)")
        }
        for msg in messages {
            let label: String
            switch msg.role {
            case .system: label = "System"
            case .user: label = "User"
            case .assistant: label = "Assistant"
            }
            parts.append("\(label): \(msg.text)")
        }
        return parts.joined(separator: "\n\n")
    }
}
