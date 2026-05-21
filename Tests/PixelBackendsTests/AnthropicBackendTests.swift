import XCTest

@testable import PixelBackends

final class AnthropicBackendTests: XCTestCase {
    func testInitWithExplicitKey() throws {
        let backend = try AnthropicBackend(apiKey: "test-key-123", modelID: "test-model")
        XCTAssertEqual(backend.modelID, "test-model")
    }

    func testInitDefaultModelID() throws {
        let backend = try AnthropicBackend(apiKey: "test-key-123")
        XCTAssertEqual(backend.modelID, "claude-sonnet-4-6")
    }

    func testInitThrowsOnEmptyKey() {
        XCTAssertThrowsError(try AnthropicBackend(apiKey: "")) { error in
            XCTAssertEqual(error as? AnthropicError, .missingAPIKey)
        }
    }

    func testErrorDescriptionLocalized() {
        XCTAssertEqual(
            AnthropicError.missingAPIKey.errorDescription,
            "ANTHROPIC_API_KEY ortam değişkeni tanımlı değil veya boş."
        )
        XCTAssertEqual(
            AnthropicError.httpError(status: 401, body: "Unauthorized").errorDescription,
            "Anthropic API HTTP 401: Unauthorized"
        )
    }
}
