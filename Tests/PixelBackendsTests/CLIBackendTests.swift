import XCTest

@testable import PixelBackends
@testable import PixelCore

final class CLIBackendTests: XCTestCase {
    func testInitWithExplicitPath() {
        let backend = CLIBackend(kind: .gemini, executablePath: "/opt/homebrew/bin/gemini")
        XCTAssertEqual(backend.kind, .gemini)
        XCTAssertEqual(backend.executablePath, "/opt/homebrew/bin/gemini")
    }

    /// **v0.2.19:** Default model ID artık her CLI için gerçek bir model adı —
    /// kullanıcı yapılandırması: Claude Opus 4.7, Codex 5.5, Gemini 3.5 Flash.
    func testDefaultModelIDFollowsKind() {
        // Env override yoksa hardcoded değerler gelmeli.
        // CI/local'da env var set değilse bu test geçer; PIXEL_*_MODEL set ise
        // override path test edilir aşağıda.
        let claudeID = CLIBackend(kind: .claude, executablePath: "/x").modelID
        let codexID = CLIBackend(kind: .codex, executablePath: "/x").modelID
        let geminiID = CLIBackend(kind: .gemini, executablePath: "/x").modelID
        // En azından default'lar non-empty ve "cli" placeholder DEĞİL.
        XCTAssertFalse(claudeID.isEmpty)
        XCTAssertFalse(codexID.isEmpty)
        XCTAssertFalse(geminiID.isEmpty)
        XCTAssertFalse(claudeID.hasSuffix("-cli"))
    }

    func testHardcodedDefaultsWhenNoEnvOverride() {
        // Env var'lar set değilse (CI'da olmaz) bu spesifik değerler beklenir.
        if ProcessInfo.processInfo.environment["PIXEL_CLAUDE_MODEL"] == nil {
            XCTAssertEqual(CLIBackend.defaultModelID(for: .claude), "claude-opus-4-7")
        }
        if ProcessInfo.processInfo.environment["PIXEL_CODEX_MODEL"] == nil {
            XCTAssertEqual(CLIBackend.defaultModelID(for: .codex), "gpt-5.5")
        }
        if ProcessInfo.processInfo.environment["PIXEL_GEMINI_MODEL"] == nil {
            XCTAssertEqual(CLIBackend.defaultModelID(for: .gemini), "gemini-3.5-flash")
        }
    }

    func testCustomModelIDOverride() {
        let backend = CLIBackend(
            kind: .claude,
            executablePath: "/x",
            modelID: "claude-sonnet-4-6"
        )
        XCTAssertEqual(backend.modelID, "claude-sonnet-4-6")
    }

    func testEchoBackendEndToEnd() async throws {
        // /bin/echo subprocess'ini CLI gibi davranan minimal bir backend olarak kullan
        let backend = CLIBackend(kind: .gemini, executablePath: "/bin/echo")
        let message = Message(role: .user, text: "test")
        var collected: [StreamDelta] = []
        for try await delta in backend.send(messages: [message], system: nil) {
            collected.append(delta)
        }
        // echo "-p <prompt>" → tek satır çıktı + .done
        // echo "-p" flag'ini argument olarak basar
        XCTAssertTrue(collected.contains(.done))
        XCTAssertGreaterThan(collected.count, 1)  // en az 1 textChunk + done
    }

    // MARK: - Plan Mode argument tests (ADR-0017)

    /// Test helper — testler için sabit bir model ID ile arguments üretir.
    private func args(for kind: CLIKind, prompt: String, options: ChatOptions = ChatOptions(), model: String = "test-model") -> [String] {
        CLIBackend.arguments(for: kind, prompt: prompt, options: options, modelID: model)
    }

    func testClaudeArgsWithoutPlanMode() {
        let a = args(for: .claude, prompt: "merhaba")
        XCTAssertFalse(a.contains("--permission-mode"))
        XCTAssertFalse(a.contains("plan"))
        XCTAssertTrue(a.contains("--output-format"))
        XCTAssertTrue(a.contains("stream-json"))
        XCTAssertEqual(a.last, "merhaba")  // prompt en sonda
    }

    func testClaudeArgsWithPlanMode() {
        let a = args(for: .claude, prompt: "merhaba", options: ChatOptions(planMode: true))
        XCTAssertTrue(a.contains("--permission-mode"))
        XCTAssertTrue(a.contains("plan"))
        // `--permission-mode plan` bitişik olmalı
        guard let idx = a.firstIndex(of: "--permission-mode") else {
            return XCTFail("--permission-mode bulunamadı")
        }
        XCTAssertEqual(a[idx + 1], "plan")
        XCTAssertEqual(a.last, "merhaba")  // prompt yine en sonda
    }

    func testCodexArgsIgnorePlanMode() {
        let off = args(for: .codex, prompt: "x")
        let on = args(for: .codex, prompt: "x", options: ChatOptions(planMode: true))
        XCTAssertEqual(off, on)  // Codex'te planMode yansımaz
        XCTAssertFalse(on.contains("--permission-mode"))
    }

    func testGeminiArgsIgnorePlanMode() {
        let off = args(for: .gemini, prompt: "x")
        let on = args(for: .gemini, prompt: "x", options: ChatOptions(planMode: true))
        XCTAssertEqual(off, on)
        XCTAssertFalse(on.contains("--permission-mode"))
    }

    /// **v0.2.18 (hotfix):** Gemini CLI'ın "trusted directory" headless promptu
    /// için `--skip-trust` her zaman geçer; promptun kendisi de korunur.
    func testGeminiArgsIncludeSkipTrust() {
        let a = args(for: .gemini, prompt: "hello")
        XCTAssertTrue(a.contains("--skip-trust"))
        XCTAssertEqual(a.last, "hello")
    }

    // MARK: - v0.2.19 — --model flag tests

    func testClaudeArgsContainModelFlag() {
        let a = args(for: .claude, prompt: "x", model: "claude-opus-4-7")
        guard let idx = a.firstIndex(of: "--model") else {
            return XCTFail("--model bulunamadı")
        }
        XCTAssertEqual(a[idx + 1], "claude-opus-4-7")
    }

    func testCodexArgsContainModelFlagAfterExec() {
        let a = args(for: .codex, prompt: "x", model: "gpt-5.5")
        guard let idx = a.firstIndex(of: "--model") else {
            return XCTFail("--model bulunamadı")
        }
        XCTAssertEqual(a[idx + 1], "gpt-5.5")
        // exec subcommand --model'den önce gelmeli
        guard let execIdx = a.firstIndex(of: "exec") else {
            return XCTFail("exec bulunamadı")
        }
        XCTAssertLessThan(execIdx, idx)
    }

    func testGeminiArgsContainModelFlag() {
        let a = args(for: .gemini, prompt: "x", model: "gemini-3.5-flash")
        guard let idx = a.firstIndex(of: "--model") else {
            return XCTFail("--model bulunamadı")
        }
        XCTAssertEqual(a[idx + 1], "gemini-3.5-flash")
        // --skip-trust hâlâ var, prompt hâlâ en sonda
        XCTAssertTrue(a.contains("--skip-trust"))
        XCTAssertEqual(a.last, "x")
    }

    func testClaudeArgsModelComesBeforePrompt() {
        let a = args(for: .claude, prompt: "merhaba", model: "claude-opus-4-7")
        guard let modelIdx = a.firstIndex(of: "claude-opus-4-7"),
              let promptIdx = a.firstIndex(of: "merhaba") else {
            return XCTFail("model veya prompt bulunamadı")
        }
        XCTAssertLessThan(modelIdx, promptIdx)
    }
}
