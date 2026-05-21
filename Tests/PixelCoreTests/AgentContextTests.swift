import XCTest

@testable import PixelCore

final class AgentContextTests: XCTestCase {
    func testDefaultIsPrimary() {
        XCTAssertEqual(AgentContext.current, .primary)
    }

    func testWithValueScopingSync() {
        XCTAssertEqual(AgentContext.current, .primary)
        AgentContext.$current.withValue(.secondary) {
            XCTAssertEqual(AgentContext.current, .secondary)
        }
        XCTAssertEqual(AgentContext.current, .primary)
    }

    func testWithValueScopingAsync() async {
        XCTAssertEqual(AgentContext.current, .primary)
        await AgentContext.$current.withValue(.secondary) {
            XCTAssertEqual(AgentContext.current, .secondary)
            await Task.yield()
            XCTAssertEqual(AgentContext.current, .secondary)
        }
        XCTAssertEqual(AgentContext.current, .primary)
    }

    func testTaskLocalPropagatesToChildTask() async {
        await AgentContext.$current.withValue(.secondary) {
            let captured = await Task { AgentContext.current }.value
            XCTAssertEqual(captured, .secondary)
        }
    }
}
