import XCTest

@testable import PixelComputerUse

final class ComputerUseErrorTests: XCTestCase {

    func testAccessibilityErrorMessage() {
        let err = ComputerUseError.accessibilityNotAuthorized
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("Accessibility"))
        XCTAssertTrue(msg.contains("System Settings"))
    }

    func testScreenRecordingErrorMessage() {
        let err = ComputerUseError.screenRecordingNotAuthorized
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("Screen Recording"))
    }

    func testNoMatchIncludesQuerySummary() {
        let query = UIQuery(bundleID: "com.apple.Safari", role: .button, title: "Done")
        let err = ComputerUseError.noMatch(query: query)
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("com.apple.Safari"))
        XCTAssertTrue(msg.contains("AXButton"))
        XCTAssertTrue(msg.contains("Done"))
    }

    func testAmbiguousMatchIncludesCount() {
        let err = ComputerUseError.ambiguousMatch(query: UIQuery(role: .button), count: 7)
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("7"))
    }

    func testTimedOutIncludesDuration() {
        let err = ComputerUseError.timedOut(after: 3.5)
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("3.5"))
    }

    func testUnsupportedIncludesReason() {
        let err = ComputerUseError.unsupported(reason: "iOS no-op")
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("iOS no-op"))
    }

    func testAxCallFailedIncludesCode() {
        let err = ComputerUseError.axCallFailed(code: -25204, hint: "AXUIElementCopyAttributeValue")
        let msg = err.errorDescription ?? ""
        XCTAssertTrue(msg.contains("-25204"))
        XCTAssertTrue(msg.contains("AXUIElementCopyAttributeValue"))
    }
}
