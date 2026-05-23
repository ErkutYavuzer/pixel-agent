import XCTest

@testable import PixelBackends
@testable import PixelCore

final class CLIBackendTests: XCTestCase {
    func testInitWithExplicitPath() {
        let backend = CLIBackend(kind: .gemini, executablePath: "/opt/homebrew/bin/gemini")
        XCTAssertEqual(backend.kind, .gemini)
        XCTAssertEqual(backend.executablePath, "/opt/homebrew/bin/gemini")
    }

    func testDefaultModelIDFollowsKind() {
        XCTAssertEqual(CLIBackend(kind: .claude, executablePath: "/x").modelID, "claude-cli")
        XCTAssertEqual(CLIBackend(kind: .codex, executablePath: "/x").modelID, "codex-cli")
        XCTAssertEqual(CLIBackend(kind: .gemini, executablePath: "/x").modelID, "gemini-cli")
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

    func testClaudeArgsWithoutPlanMode() {
        let args = CLIBackend.arguments(for: .claude, prompt: "merhaba", options: ChatOptions())
        XCTAssertFalse(args.contains("--permission-mode"))
        XCTAssertFalse(args.contains("plan"))
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertEqual(args.last, "merhaba")  // prompt en sonda
    }

    func testClaudeArgsWithPlanMode() {
        let args = CLIBackend.arguments(
            for: .claude,
            prompt: "merhaba",
            options: ChatOptions(planMode: true)
        )
        XCTAssertTrue(args.contains("--permission-mode"))
        XCTAssertTrue(args.contains("plan"))
        // `--permission-mode plan` bitişik olmalı
        guard let idx = args.firstIndex(of: "--permission-mode") else {
            return XCTFail("--permission-mode bulunamadı")
        }
        XCTAssertEqual(args[idx + 1], "plan")
        XCTAssertEqual(args.last, "merhaba")  // prompt yine en sonda
    }

    func testCodexArgsIgnorePlanMode() {
        let off = CLIBackend.arguments(for: .codex, prompt: "x", options: ChatOptions())
        let on = CLIBackend.arguments(for: .codex, prompt: "x", options: ChatOptions(planMode: true))
        XCTAssertEqual(off, on)  // Codex'te planMode yansımaz
        XCTAssertFalse(on.contains("--permission-mode"))
    }

    func testGeminiArgsIgnorePlanMode() {
        let off = CLIBackend.arguments(for: .gemini, prompt: "x", options: ChatOptions())
        let on = CLIBackend.arguments(for: .gemini, prompt: "x", options: ChatOptions(planMode: true))
        XCTAssertEqual(off, on)
        XCTAssertFalse(on.contains("--permission-mode"))
    }

    /// **v0.2.18 (hotfix):** Gemini CLI'ın "trusted directory" headless promptu
    /// için `--skip-trust` her zaman geçer; promptun kendisi de korunur.
    func testGeminiArgsIncludeSkipTrust() {
        let args = CLIBackend.arguments(for: .gemini, prompt: "hello", options: ChatOptions())
        XCTAssertTrue(args.contains("--skip-trust"))
        XCTAssertEqual(args.last, "hello")
    }
}
