import XCTest

@testable import PixelMacApp

@MainActor
final class ScreenshotStreamCoordinatorTests: XCTestCase {

    // MARK: - Initial state

    func testInitialIsActiveFalse() {
        let coordinator = ScreenshotStreamCoordinator()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(coordinator.intervalMs, 1000)
    }

    // MARK: - Start / stop lifecycle

    func testStartSetsIsActiveTrue() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 1000) { _, _, _ in }
        XCTAssertTrue(coordinator.isActive)
        coordinator.stop()
    }

    func testStopSetsIsActiveFalse() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 1000) { _, _, _ in }
        coordinator.stop()
        XCTAssertFalse(coordinator.isActive)
    }

    func testStopIdempotent() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.stop() // never started
        XCTAssertFalse(coordinator.isActive)
        coordinator.stop() // double stop
        XCTAssertFalse(coordinator.isActive)
    }

    func testStartCancelsPreviousIntervalState() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 5000) { _, _, _ in }
        XCTAssertEqual(coordinator.intervalMs, 5000)
        coordinator.start(intervalMs: 1000) { _, _, _ in }
        XCTAssertEqual(coordinator.intervalMs, 1000)
        // İkinci start öncekini cancel'lar (test edilen: state değişimi).
        XCTAssertTrue(coordinator.isActive)
        coordinator.stop()
    }

    // MARK: - Interval clamping

    func testClampingBelowMinimum() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 50) { _, _, _ in }
        XCTAssertEqual(coordinator.intervalMs, 250) // min cap
        coordinator.stop()
    }

    func testClampingAboveMaximum() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 99999) { _, _, _ in }
        XCTAssertEqual(coordinator.intervalMs, 5000) // max cap
        coordinator.stop()
    }

    func testValidIntervalUnchanged() {
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 2500) { _, _, _ in }
        XCTAssertEqual(coordinator.intervalMs, 2500)
        coordinator.stop()
    }

    // MARK: - Sprint 17: Upstream cancellation semantics

    func testStopImmediatelyTransitionsIsActive() {
        // Sprint 17 follow-up: stop'un syncron olarak isActive false yapması
        // bekleniyor (ChatHost.onChange handler'ı immediate UI update için).
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 5000) { _, _, _ in }
        XCTAssertTrue(coordinator.isActive)

        coordinator.stop()
        XCTAssertFalse(coordinator.isActive,
            "stop() çağrısı sonrası isActive sync olarak false olmalı — Task end async olabilir ama state immediate")
    }

    // MARK: - Sprint 22: Wire-level latency

    func testInitialWireLatencyIsNil() {
        // Yeni coordinator: hiç ACK gelmedi → lastWireLatencyMs nil.
        let coordinator = ScreenshotStreamCoordinator()
        XCTAssertNil(coordinator.lastWireLatencyMs)
    }

    func testRecordAckWithUnknownFrameIDNoOp() {
        // Stream başlat ama gönderilmemiş bir frameID'ye ACK gelirse:
        // state değişmez, lastWireLatencyMs nil kalır.
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 5000) { _, _, _ in }

        coordinator.recordAck(frameID: "fake-id-never-sent", at: Date())
        XCTAssertNil(coordinator.lastWireLatencyMs,
            "Eşleşmeyen ACK no-op olmalı")

        coordinator.stop()
    }

    func testStartResetsWireLatencyState() {
        // Önceki stream'in wire latency state'i yeni stream'e taşınmamalı.
        let coordinator = ScreenshotStreamCoordinator()
        coordinator.start(intervalMs: 1000) { _, _, _ in }
        coordinator.stop()

        coordinator.start(intervalMs: 1000) { _, _, _ in }
        XCTAssertNil(coordinator.lastWireLatencyMs,
            "Re-start lastWireLatencyMs'i nil'e reset etmeli")
        coordinator.stop()
    }
}
