import XCTest

@testable import PixelMacApp

final class ConnectionTransitionDetectorTests: XCTestCase {

    // MARK: - Loss event = connected → disconnected

    func testConnectedToDisconnectedIsLoss() {
        XCTAssertTrue(
            ConnectionTransitionDetector.isLossEvent(
                from: .connected, to: .disconnected
            )
        )
    }

    // MARK: - Non-loss transitions

    func testConnectedToNotPairedIsNotLoss() {
        // Kullanıcı eşleşmeyi sıfırladı — niyetli, pulse istemiyoruz.
        XCTAssertFalse(
            ConnectionTransitionDetector.isLossEvent(
                from: .connected, to: .notPaired
            )
        )
    }

    func testConnectedToConnectingIsNotLoss() {
        // Pair re-handshake gibi geçici durum, pulse spam etmesin.
        XCTAssertFalse(
            ConnectionTransitionDetector.isLossEvent(
                from: .connected, to: .connecting
            )
        )
    }

    func testNotPairedToConnectingIsNotLoss() {
        XCTAssertFalse(
            ConnectionTransitionDetector.isLossEvent(
                from: .notPaired, to: .connecting
            )
        )
    }

    func testConnectingToConnectedIsNotLoss() {
        // Pozitif transition — kesinlikle loss değil.
        XCTAssertFalse(
            ConnectionTransitionDetector.isLossEvent(
                from: .connecting, to: .connected
            )
        )
    }

    func testDisconnectedToConnectedIsNotLoss() {
        // Reconnect — pulse uygun değil.
        XCTAssertFalse(
            ConnectionTransitionDetector.isLossEvent(
                from: .disconnected, to: .connected
            )
        )
    }

    func testSameStateIsNotLoss() {
        // Idempotent re-render senaryosu.
        for state in [ConnectionPillState.notPaired, .connecting, .disconnected, .connected] {
            XCTAssertFalse(
                ConnectionTransitionDetector.isLossEvent(from: state, to: state),
                "Aynı state self-transition loss sayılmamalı: \(state)"
            )
        }
    }
}
