import XCTest

@testable import PixelComputerUse

final class MacroReplayPlanTests: XCTestCase {
    private let click = MacroStep.click(query: nil, opaqueID: "x", count: 1, modifiers: [])
    private let wait = MacroStep.wait(milliseconds: 10)

    // MARK: - validate

    func testValidateEmptyFails() {
        XCTAssertEqual(MacroReplayPlan.validate([], maxSteps: 200), .failure(.emptyRecording))
    }

    func testValidateTooManyFails() {
        let steps = Array(repeating: wait, count: 5)
        XCTAssertEqual(MacroReplayPlan.validate(steps, maxSteps: 3), .failure(.tooManySteps(count: 5, max: 3)))
    }

    func testValidateOKPreservesOrder() {
        let steps: [MacroStep] = [click, wait, click]
        XCTAssertEqual(MacroReplayPlan.validate(steps, maxSteps: 200), .success(steps))
    }

    // MARK: - decideOnNotFound

    func testDecideAbortPolicy() {
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: .abort, attempt: 0), .abort)
    }

    func testDecideSkipPolicy() {
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: .skip, attempt: 0), .skip)
    }

    func testDecideRetryThenAbort() {
        let policy = NotFoundPolicy.retry(maxRetries: 2, backoffMs: 300)
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: policy, attempt: 0), .retry(afterMs: 300))
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: policy, attempt: 1), .retry(afterMs: 300))
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: policy, attempt: 2), .abort)
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: policy, attempt: 3), .abort)
    }

    func testDecideRetryNegativeBackoffClampedToZero() {
        let policy = NotFoundPolicy.retry(maxRetries: 1, backoffMs: -50)
        XCTAssertEqual(MacroReplayPlan.decideOnNotFound(policy: policy, attempt: 0), .retry(afterMs: 0))
    }

    // MARK: - Plan Mode guard

    func testBlockedByPlanModeWhenDestructiveAndNotAllowed() {
        XCTAssertTrue(MacroReplayPlan.isBlockedByPlanMode([click], allowDestructive: false))
    }

    func testNotBlockedWhenAllowed() {
        XCTAssertFalse(MacroReplayPlan.isBlockedByPlanMode([click], allowDestructive: true))
    }

    func testNotBlockedWhenNoDestructiveSteps() {
        let readOnly: [MacroStep] = [.screenshot(target: .activeDisplay), .wait(milliseconds: 5)]
        XCTAssertFalse(MacroReplayPlan.isBlockedByPlanMode(readOnly, allowDestructive: false))
    }
}
