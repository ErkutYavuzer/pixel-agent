import Foundation
import XCTest

@testable import PixelMacApp

/// **Sprint 22 (v0.2.47):** `WireLatencyTracker` saf helper'ı.
/// In/out `WireLatencyState` struct'ı caller'ın tuttuğu durum; tracker
/// enum static funcs üzerinden okur/yazar. Tüm test'ler deterministik —
/// `Date(timeIntervalSince1970:)` ile sabit zaman.
final class WireLatencyTrackerTests: XCTestCase {

    // MARK: - record

    func testRecordSavesFrameIDWithSentAt() {
        var state = WireLatencyState()
        let t0 = Date(timeIntervalSince1970: 1_000)
        WireLatencyTracker.record(state: &state, frameID: "f1", at: t0)

        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.pending["f1"], t0)
    }

    func testRecordOverwriteSameFrameID() {
        // Aynı frameID iki kez kaydedilirse son sentAt galip — defensive
        // (production'da UUID kullanılır, çakışma olmaz).
        var state = WireLatencyState()
        let early = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 1_500)
        WireLatencyTracker.record(state: &state, frameID: "f1", at: early)
        WireLatencyTracker.record(state: &state, frameID: "f1", at: later)

        XCTAssertEqual(state.pending["f1"], later)
    }

    // MARK: - consumeAck

    func testConsumeAckMatchedReturnsLatencyAndUpdatesState() {
        var state = WireLatencyState()
        let sentAt = Date(timeIntervalSince1970: 1_000)
        let receivedAt = Date(timeIntervalSince1970: 1_000.123) // 123 ms sonra
        WireLatencyTracker.record(state: &state, frameID: "f1", at: sentAt)

        let latency = WireLatencyTracker.consumeAck(
            state: &state,
            frameID: "f1",
            receivedAt: receivedAt
        )

        XCTAssertEqual(latency, 123)
        XCTAssertEqual(state.lastWireLatencyMs, 123)
        XCTAssertEqual(state.lastAckAt, receivedAt)
        XCTAssertNil(state.pending["f1"], "Consume sonrası pending'den silinmeli")
    }

    func testConsumeAckUnmatchedReturnsNilStateUnchanged() {
        var state = WireLatencyState()
        let receivedAt = Date(timeIntervalSince1970: 1_000)

        let latency = WireLatencyTracker.consumeAck(
            state: &state,
            frameID: "never-sent",
            receivedAt: receivedAt
        )

        XCTAssertNil(latency)
        XCTAssertNil(state.lastWireLatencyMs)
        XCTAssertNil(state.lastAckAt)
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testConsumeAckNegativeLatencyClampedToZero() {
        // Saat sapması: receivedAt < sentAt olursa defensive 0'a clamp.
        var state = WireLatencyState()
        let sentAt = Date(timeIntervalSince1970: 1_500)
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        WireLatencyTracker.record(state: &state, frameID: "f1", at: sentAt)

        let latency = WireLatencyTracker.consumeAck(
            state: &state,
            frameID: "f1",
            receivedAt: receivedAt
        )

        XCTAssertEqual(latency, 0)
        XCTAssertEqual(state.lastWireLatencyMs, 0)
    }

    func testConsumeAckSinglePendingOnly() {
        // Diğer pending entry'ler etkilenmemeli.
        var state = WireLatencyState()
        let t = Date(timeIntervalSince1970: 1_000)
        WireLatencyTracker.record(state: &state, frameID: "f1", at: t)
        WireLatencyTracker.record(state: &state, frameID: "f2", at: t)
        WireLatencyTracker.record(state: &state, frameID: "f3", at: t)

        _ = WireLatencyTracker.consumeAck(
            state: &state,
            frameID: "f2",
            receivedAt: t.addingTimeInterval(0.05)
        )

        XCTAssertEqual(state.pending.count, 2)
        XCTAssertNotNil(state.pending["f1"])
        XCTAssertNil(state.pending["f2"])
        XCTAssertNotNil(state.pending["f3"])
    }

    // MARK: - prune

    func testPruneRemovesOlderEntries() {
        var state = WireLatencyState()
        let old1 = Date(timeIntervalSince1970: 1_000)
        let old2 = Date(timeIntervalSince1970: 1_010)
        let fresh = Date(timeIntervalSince1970: 2_000)
        WireLatencyTracker.record(state: &state, frameID: "old1", at: old1)
        WireLatencyTracker.record(state: &state, frameID: "old2", at: old2)
        WireLatencyTracker.record(state: &state, frameID: "fresh", at: fresh)

        // cutoff: 1_500 → 1_000 ve 1_010 silinmeli, 2_000 kalmalı.
        let cutoff = Date(timeIntervalSince1970: 1_500)
        WireLatencyTracker.prune(state: &state, olderThan: cutoff)

        XCTAssertEqual(state.pending.count, 1)
        XCTAssertNotNil(state.pending["fresh"])
    }

    func testPruneCutoffBoundary() {
        // sentAt == cutoff → silinmeli (strict ">" kullanılır).
        var state = WireLatencyState()
        let cutoff = Date(timeIntervalSince1970: 1_000)
        WireLatencyTracker.record(state: &state, frameID: "at-cutoff", at: cutoff)
        WireLatencyTracker.record(
            state: &state,
            frameID: "above-cutoff",
            at: cutoff.addingTimeInterval(0.001)
        )

        WireLatencyTracker.prune(state: &state, olderThan: cutoff)

        XCTAssertNil(state.pending["at-cutoff"], "Sınırdaki entry silinmeli")
        XCTAssertNotNil(state.pending["above-cutoff"])
    }

    func testPruneEmptyStateNoOp() {
        var state = WireLatencyState()
        WireLatencyTracker.prune(state: &state, olderThan: Date())
        XCTAssertTrue(state.pending.isEmpty)
    }

    // MARK: - effectiveLatencyMs

    func testEffectiveLatencyNoAckEverReturnsLocal() {
        // Hiç ACK gelmemiş → her zaman local fallback.
        let state = WireLatencyState()
        let latency = WireLatencyTracker.effectiveLatencyMs(
            state: state,
            localMs: 200,
            now: Date()
        )
        XCTAssertEqual(latency, 200)
    }

    func testEffectiveLatencyFreshAckReturnsWire() {
        // ACK son 5 sn içinde → wire latency kullanılır.
        let now = Date(timeIntervalSince1970: 1_000)
        let ackAt = now.addingTimeInterval(-2) // 2 sn önce
        var state = WireLatencyState()
        state.lastWireLatencyMs = 85
        state.lastAckAt = ackAt

        let latency = WireLatencyTracker.effectiveLatencyMs(
            state: state,
            localMs: 200,
            now: now
        )
        XCTAssertEqual(latency, 85, "Fresh ACK varken wire latency kullanılmalı")
    }

    func testEffectiveLatencyStaleAckReturnsLocal() {
        // ACK çok eski (10 sn önce, default freshness 5 sn) → local'a düş.
        let now = Date(timeIntervalSince1970: 1_000)
        let ackAt = now.addingTimeInterval(-10)
        var state = WireLatencyState()
        state.lastWireLatencyMs = 85
        state.lastAckAt = ackAt

        let latency = WireLatencyTracker.effectiveLatencyMs(
            state: state,
            localMs: 200,
            now: now
        )
        XCTAssertEqual(latency, 200, "Stale ACK varken local fallback kullanılmalı")
    }

    func testEffectiveLatencyFreshnessThresholdConfigurable() {
        // freshnessSeconds custom — 1 sn'lik dar pencere.
        let now = Date(timeIntervalSince1970: 1_000)
        let ackAt = now.addingTimeInterval(-2) // 2 sn önce, threshold 1 sn
        var state = WireLatencyState()
        state.lastWireLatencyMs = 85
        state.lastAckAt = ackAt

        let latency = WireLatencyTracker.effectiveLatencyMs(
            state: state,
            localMs: 200,
            now: now,
            freshnessSeconds: 1
        )
        XCTAssertEqual(latency, 200, "Custom threshold dışı ACK stale sayılmalı")
    }

    func testEffectiveLatencyWireIsZeroStillUsedIfFresh() {
        // Wire latency 0 ms (yerel test bağlantısı) — fresh ise yine
        // wire kullanılır; "0 == nil" yorumlamayız.
        let now = Date()
        var state = WireLatencyState()
        state.lastWireLatencyMs = 0
        state.lastAckAt = now.addingTimeInterval(-0.5)

        let latency = WireLatencyTracker.effectiveLatencyMs(
            state: state,
            localMs: 200,
            now: now
        )
        XCTAssertEqual(latency, 0, "Fresh wire latency 0 ise yine kullanılmalı")
    }

    // MARK: - State equality / defaults

    func testInitialStateEmpty() {
        let state = WireLatencyState()
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertNil(state.lastWireLatencyMs)
        XCTAssertNil(state.lastAckAt)
    }

    func testStateEquatable() {
        // Equatable synthesis düzgün — Sendable struct, ChatHost diffing'i
        // ileride bu state'i UI'a yansıtabilir.
        let t = Date(timeIntervalSince1970: 1_000)
        let a = WireLatencyState(
            pending: ["f1": t],
            lastWireLatencyMs: 42,
            lastAckAt: t
        )
        let b = WireLatencyState(
            pending: ["f1": t],
            lastWireLatencyMs: 42,
            lastAckAt: t
        )
        XCTAssertEqual(a, b)
    }
}
