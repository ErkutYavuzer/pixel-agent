import XCTest

@testable import PixelMacApp

final class ConnectionPillStateTests: XCTestCase {

    // MARK: - State derivation

    func testNotPairedFromBothFalse() {
        XCTAssertEqual(
            ConnectionPillState.from(isPaired: false, isConnected: false),
            .notPaired
        )
    }

    func testConnectingFromNotPairedButConnected() {
        // Pair handshake yarıda — transport açık, henüz pair envelope onaylanmamış.
        XCTAssertEqual(
            ConnectionPillState.from(isPaired: false, isConnected: true),
            .connecting
        )
    }

    func testDisconnectedFromPairedButOffline() {
        // RemoteHost pair history'yi disconnect()'te düşürüyor; bu state pratikte
        // nadir görülür ama defensive.
        XCTAssertEqual(
            ConnectionPillState.from(isPaired: true, isConnected: false),
            .disconnected
        )
    }

    func testConnectedFromBothTrue() {
        XCTAssertEqual(
            ConnectionPillState.from(isPaired: true, isConnected: true),
            .connected
        )
    }

    // MARK: - Display metadata non-empty

    func testEveryStateHasNonEmptyLabelImageAndHelp() {
        for state in [
            ConnectionPillState.notPaired,
            .connecting,
            .disconnected,
            .connected
        ] {
            XCTAssertFalse(state.label.isEmpty, "label boş: \(state)")
            XCTAssertFalse(state.systemImage.isEmpty, "systemImage boş: \(state)")
            XCTAssertFalse(state.helpText.isEmpty, "helpText boş: \(state)")
        }
    }

    func testLabelsAreUnique() {
        let labels: [String] = [
            ConnectionPillState.notPaired.label,
            ConnectionPillState.connecting.label,
            ConnectionPillState.disconnected.label,
            ConnectionPillState.connected.label,
        ]
        XCTAssertEqual(Set(labels).count, labels.count, "Duplicate label var")
    }

    // MARK: - Tint mapping

    func testTintPerState() {
        XCTAssertEqual(ConnectionPillState.notPaired.tint, .gray)
        XCTAssertEqual(ConnectionPillState.connecting.tint, .yellow)
        XCTAssertEqual(ConnectionPillState.disconnected.tint, .orange)
        XCTAssertEqual(ConnectionPillState.connected.tint, .green)
    }

    func testConnectedStateUsesAffirmativeIcon() {
        // Demo senaryosunda yeşil "iPhone bağlı" pill açık olmalı —
        // regression guard: ikonun "slash" türevi değil, radiowaves olduğu.
        XCTAssertTrue(
            ConnectionPillState.connected.systemImage.contains("radiowaves"),
            "Bağlı durumda radiowaves bekleniyor"
        )
        XCTAssertFalse(ConnectionPillState.connected.systemImage.contains("slash"))
    }
}
