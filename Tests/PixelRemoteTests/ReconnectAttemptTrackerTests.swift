import XCTest
@testable import PixelRemote

/// **Sprint 35 (v0.2.62):** ReconnectAttemptTracker saf değer tipi testleri.
/// iOS RemoteSession stale-pairing detection logic'inin temel kontratları.
final class ReconnectAttemptTrackerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsHealthy() {
        let tracker = ReconnectAttemptTracker()
        XCTAssertEqual(tracker.connectFailureCount, 0)
        XCTAssertEqual(tracker.verifyFailureCount, 0)
        XCTAssertFalse(tracker.isPairingStaleSuspected)
    }

    func testDefaultThresholdsAreReasonable() {
        // 5 connect fail = ~30s exponential backoff (2+4+8+16 = 30s)
        XCTAssertEqual(ReconnectAttemptTracker.defaultConnectFailureThreshold, 5)
        // 3 verify fail = highly likely key mismatch
        XCTAssertEqual(ReconnectAttemptTracker.defaultVerifyFailureThreshold, 3)
        // 8s ready timeout — Mac hostStatus/assistantChunk normalde anlık
        XCTAssertEqual(ReconnectAttemptTracker.defaultReadyTimeoutSeconds, 8)
    }

    func testCustomInitClampsNegativeThresholdsTo1() {
        let tracker = ReconnectAttemptTracker(
            connectFailureThreshold: -3,
            verifyFailureThreshold: 0
        )
        XCTAssertEqual(tracker.connectFailureThreshold, 1)
        XCTAssertEqual(tracker.verifyFailureThreshold, 1)
    }

    func testCustomInitClampsNegativeCountsToZero() {
        let tracker = ReconnectAttemptTracker(
            connectFailureCount: -5,
            verifyFailureCount: -10
        )
        XCTAssertEqual(tracker.connectFailureCount, 0)
        XCTAssertEqual(tracker.verifyFailureCount, 0)
    }

    // MARK: - Connect failure threshold

    func testConnectFailureBelowThresholdIsHealthy() {
        var tracker = ReconnectAttemptTracker(connectFailureThreshold: 5)
        for _ in 0..<4 {
            tracker.recordConnectFailure()
        }
        XCTAssertEqual(tracker.connectFailureCount, 4)
        XCTAssertFalse(tracker.isPairingStaleSuspected)
    }

    func testConnectFailureAtThresholdTriggersStaleSuspected() {
        var tracker = ReconnectAttemptTracker(connectFailureThreshold: 5)
        for _ in 0..<5 {
            tracker.recordConnectFailure()
        }
        XCTAssertEqual(tracker.connectFailureCount, 5)
        XCTAssertTrue(tracker.isPairingStaleSuspected)
    }

    func testConnectFailureAboveThresholdRemainsStale() {
        var tracker = ReconnectAttemptTracker(connectFailureThreshold: 3)
        for _ in 0..<10 {
            tracker.recordConnectFailure()
        }
        XCTAssertEqual(tracker.connectFailureCount, 10)
        XCTAssertTrue(tracker.isPairingStaleSuspected)
    }

    // MARK: - Verify failure threshold

    func testVerifyFailureBelowThresholdIsHealthy() {
        var tracker = ReconnectAttemptTracker(verifyFailureThreshold: 3)
        for _ in 0..<2 {
            tracker.recordVerifyFailure()
        }
        XCTAssertEqual(tracker.verifyFailureCount, 2)
        XCTAssertFalse(tracker.isPairingStaleSuspected)
    }

    func testVerifyFailureAtThresholdTriggersStaleSuspected() {
        var tracker = ReconnectAttemptTracker(verifyFailureThreshold: 3)
        for _ in 0..<3 {
            tracker.recordVerifyFailure()
        }
        XCTAssertEqual(tracker.verifyFailureCount, 3)
        XCTAssertTrue(tracker.isPairingStaleSuspected)
    }

    func testVerifyAndConnectThresholdsAreIndependent() {
        // 4 connect fail (threshold 5'in altında) + 3 verify fail (threshold)
        // → stale (verify path).
        var tracker = ReconnectAttemptTracker(
            connectFailureThreshold: 5,
            verifyFailureThreshold: 3
        )
        for _ in 0..<4 { tracker.recordConnectFailure() }
        for _ in 0..<3 { tracker.recordVerifyFailure() }
        XCTAssertTrue(tracker.isPairingStaleSuspected, "Verify threshold alone yeterli olmalı")
    }

    // MARK: - Success resets

    func testRecordSuccessResetsBothCounters() {
        var tracker = ReconnectAttemptTracker()
        for _ in 0..<3 { tracker.recordConnectFailure() }
        for _ in 0..<2 { tracker.recordVerifyFailure() }
        tracker.recordSuccess()
        XCTAssertEqual(tracker.connectFailureCount, 0)
        XCTAssertEqual(tracker.verifyFailureCount, 0)
        XCTAssertFalse(tracker.isPairingStaleSuspected)
    }

    func testRecordSuccessAfterStaleClearsFlag() {
        var tracker = ReconnectAttemptTracker(connectFailureThreshold: 2)
        tracker.recordConnectFailure()
        tracker.recordConnectFailure()
        XCTAssertTrue(tracker.isPairingStaleSuspected)
        tracker.recordSuccess()
        XCTAssertFalse(tracker.isPairingStaleSuspected)
    }

    // MARK: - Defensive

    func testOverflowSafety() {
        // Int.max'a yakın değerle başla, recordConnectFailure çağrısı saturate
        // etmeli, negatife wrap etmemeli.
        var tracker = ReconnectAttemptTracker(
            connectFailureCount: Int.max
        )
        tracker.recordConnectFailure()
        XCTAssertGreaterThanOrEqual(tracker.connectFailureCount, 0)
        XCTAssertTrue(tracker.isPairingStaleSuspected)
    }

    func testEquatable() {
        let a = ReconnectAttemptTracker(
            connectFailureThreshold: 5,
            verifyFailureThreshold: 3,
            connectFailureCount: 2,
            verifyFailureCount: 1
        )
        let b = ReconnectAttemptTracker(
            connectFailureThreshold: 5,
            verifyFailureThreshold: 3,
            connectFailureCount: 2,
            verifyFailureCount: 1
        )
        let c = ReconnectAttemptTracker(
            connectFailureThreshold: 5,
            verifyFailureThreshold: 3,
            connectFailureCount: 3,
            verifyFailureCount: 1
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Demo scenario regression

    /// **Demo senaryosu:** Mac restart + iOS saved pairing stale. Reconnect
    /// loop 5 fail → UI prompt. Kullanıcı QR'ı tarar (forgetAndRescan tracker'ı
    /// sıfırlar) → ilk envelope verify pass → recordSuccess → healthy.
    func testDemoScenario_StaleToRecovery() {
        var tracker = ReconnectAttemptTracker()
        // Reconnect loop 5 fail
        for _ in 0..<5 { tracker.recordConnectFailure() }
        XCTAssertTrue(tracker.isPairingStaleSuspected)

        // Kullanıcı forgetAndRescan: fresh tracker
        tracker = ReconnectAttemptTracker()
        XCTAssertFalse(tracker.isPairingStaleSuspected)

        // Yeni QR sonrası ilk envelope verify pass
        tracker.recordSuccess()
        XCTAssertFalse(tracker.isPairingStaleSuspected)
    }
}
