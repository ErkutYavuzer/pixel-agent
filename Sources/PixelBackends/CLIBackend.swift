import Foundation
import PixelCore

public struct CLIBackend: ChatBackend {
    public let kind: CLIKind
    public let modelID: String
    public let executablePath: String

    public init(kind: CLIKind, executablePath: String, modelID: String? = nil) {
        self.kind = kind
        self.executablePath = executablePath
        self.modelID = modelID ?? "\(kind.rawValue)-cli"
    }

    public init(kind: CLIKind, detector: CLIDetector = CLIDetector()) throws {
        guard let path = detector.locate(kind) else {
            throw BackendError.cliNotFound(name: kind.executableName)
        }
        self.init(kind: kind, executablePath: path)
    }

    public func send(
        messages: [Message],
        system: String?,
        options: ChatOptions
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        let prompt = Self.composedPrompt(messages: messages, system: system)
        let kind = self.kind
        let executablePath = self.executablePath

        return AsyncThrowingStream { continuation in
            let task = Task {
                let stdin: String? = Self.usesStdinForPrompt(for: kind) ? prompt : nil
                let runner = CLIProcessRunner(
                    executablePath: executablePath,
                    arguments: Self.arguments(for: kind, prompt: prompt, options: options)
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
    static func arguments(for kind: CLIKind, prompt: String, options: ChatOptions) -> [String] {
        switch kind {
        case .claude:
            var args = [
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
                "--json",
                "--ignore-user-config",
                "--skip-git-repo-check",
                "--dangerously-bypass-approvals-and-sandbox",
                "-",
            ]
        case .gemini:
            // Gemini CLI Plan Mode'a native destek vermiyor — bayrak yok.
            return ["-p", prompt]
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
