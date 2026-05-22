import XCTest
@testable import PixelSubagent

final class SubagentResultTests: XCTestCase {
    func testOutputAccessorAcrossAllCases() {
        XCTAssertEqual(SubagentResult.completed(output: "x", durationSeconds: 1).output, "x")
        XCTAssertEqual(SubagentResult.budgetExceeded(reason: .duration, partialOutput: "y", durationSeconds: 1).output, "y")
        XCTAssertEqual(SubagentResult.cancelled(partialOutput: "z", durationSeconds: 1).output, "z")
        XCTAssertEqual(SubagentResult.failed(error: "e", partialOutput: "w", durationSeconds: 1).output, "w")
    }

    func testIsCompletedFlag() {
        XCTAssertTrue(SubagentResult.completed(output: "", durationSeconds: 0).isCompleted)
        XCTAssertFalse(SubagentResult.budgetExceeded(reason: .duration, partialOutput: "", durationSeconds: 0).isCompleted)
        XCTAssertFalse(SubagentResult.cancelled(partialOutput: "", durationSeconds: 0).isCompleted)
        XCTAssertFalse(SubagentResult.failed(error: "", partialOutput: "", durationSeconds: 0).isCompleted)
    }

    func testDurationAccessor() {
        XCTAssertEqual(SubagentResult.completed(output: "", durationSeconds: 1.5).durationSeconds, 1.5)
        XCTAssertEqual(SubagentResult.budgetExceeded(reason: .outputBytes, partialOutput: "", durationSeconds: 2.5).durationSeconds, 2.5)
    }

    func testBudgetReasonValues() {
        XCTAssertEqual(SubagentResult.BudgetReason.duration.rawValue, "duration")
        XCTAssertEqual(SubagentResult.BudgetReason.outputBytes.rawValue, "outputBytes")
    }
}
