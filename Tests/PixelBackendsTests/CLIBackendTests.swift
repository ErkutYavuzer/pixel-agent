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
}
