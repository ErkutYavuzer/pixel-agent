import XCTest

@testable import PixelRemote

final class ConnectionLossDetectorTests: XCTestCase {

    // MARK: - Loss event

    func testConnectedToDisconnectedIsLoss() {
        XCTAssertTrue(
            ConnectionLossDetector.isLossEvent(
                wasConnected: true, isConnected: false
            )
        )
    }

    // MARK: - Non-loss

    func testDisconnectedToConnectedIsNotLoss() {
        XCTAssertFalse(
            ConnectionLossDetector.isLossEvent(
                wasConnected: false, isConnected: true
            )
        )
    }

    func testStableConnectedIsNotLoss() {
        XCTAssertFalse(
            ConnectionLossDetector.isLossEvent(
                wasConnected: true, isConnected: true
            )
        )
    }

    func testStableDisconnectedIsNotLoss() {
        XCTAssertFalse(
            ConnectionLossDetector.isLossEvent(
                wasConnected: false, isConnected: false
            )
        )
    }

    // MARK: - Exhaustive truth table

    func testTruthTableCoverage() {
        let cases: [(Bool, Bool, Bool)] = [
            (false, false, false),
            (false, true, false),
            (true, false, true),
            (true, true, false),
        ]
        for (was, current, expected) in cases {
            XCTAssertEqual(
                ConnectionLossDetector.isLossEvent(
                    wasConnected: was, isConnected: current
                ),
                expected,
                "(was=\(was), is=\(current)) → \(expected) bekleniyor"
            )
        }
    }
}
