import XCTest
@testable import PixelMacApp

/// **Sprint 38 (v0.2.65):** ProactiveRateLimiter karar tablosu testleri.
final class ProactiveRateLimiterTests: XCTestCase {

    func testEmptyLimiterAllowsFire() {
        let limiter = ProactiveRateLimiter()
        XCTAssertTrue(limiter.canFire(.idle))
        XCTAssertTrue(limiter.canFire(.appChange))
    }

    func testJustFiredKindBlocksItselfWithinCooldown() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter()
        limiter.record(kind: .idle, at: now)
        // 1 saniye sonra hâlâ cooldown'da
        XCTAssertFalse(limiter.canFire(.idle, now: now.addingTimeInterval(1)))
    }

    func testJustFiredKindBlocksOtherViaGlobalCooldown() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter()
        limiter.record(kind: .idle, at: now)
        // appChange başka kind ama global cooldown da var → bloklu
        XCTAssertFalse(limiter.canFire(.appChange, now: now.addingTimeInterval(60)))
    }

    func testFiredAllowsAgainAfterCooldown() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter()
        limiter.record(kind: .idle, at: now)
        // Default global cooldown = 300s. 301s sonra serbest.
        XCTAssertTrue(limiter.canFire(.idle, now: now.addingTimeInterval(301)))
    }

    func testCustomGlobalCooldown() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter(globalCooldownSeconds: 30)
        limiter.record(kind: .idle, at: now)
        XCTAssertFalse(limiter.canFire(.idle, now: now.addingTimeInterval(29)))
        XCTAssertTrue(limiter.canFire(.idle, now: now.addingTimeInterval(31)))
    }

    func testNegativeGlobalCooldownClampsToZero() {
        let limiter = ProactiveRateLimiter(globalCooldownSeconds: -5)
        XCTAssertEqual(limiter.globalCooldownSeconds, 0)
    }

    func testPerKindCooldownOverride() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter(globalCooldownSeconds: 30)
        limiter.setCooldown(120, for: .appChange)
        XCTAssertEqual(limiter.effectiveCooldown(for: .appChange), 120)
        XCTAssertEqual(limiter.effectiveCooldown(for: .idle), 30)  // global

        limiter.record(kind: .appChange, at: now)
        // 60 saniye sonra global cooldown (30) bitti ama appChange'in özel
        // override'ı (120) hâlâ aktif. Yine de canFire global'i geçtikten
        // sonra per-kind kontrol eder. Edit: bu test global+kind kombinasyonu.
        // 31s sonra: global 30 bitti, kind cooldown 120 hâlâ blok.
        XCTAssertFalse(limiter.canFire(.appChange, now: now.addingTimeInterval(31)))
        // 121s sonra: hem global hem kind bitti.
        XCTAssertTrue(limiter.canFire(.appChange, now: now.addingTimeInterval(121)))
    }

    func testRecordUpdatesLastFires() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter()
        XCTAssertNil(limiter.lastFires[.idle])
        limiter.record(kind: .idle, at: now)
        XCTAssertEqual(limiter.lastFires[.idle], now)
    }

    func testMostRecentDeterminesGlobalCooldown() {
        let baseNow = Date(timeIntervalSince1970: 10_000)
        var limiter = ProactiveRateLimiter()
        // appChange 100s önce fired
        limiter.record(kind: .appChange, at: baseNow.addingTimeInterval(-100))
        // idle 10s önce fired (en yakın)
        limiter.record(kind: .idle, at: baseNow.addingTimeInterval(-10))
        // appChange canFire? Global cooldown idle'ın en yakın olduğu için 290s eksik.
        XCTAssertFalse(limiter.canFire(.appChange, now: baseNow))
    }

    func testCustomInitializerPreservesLastFires() {
        let now = Date(timeIntervalSince1970: 10_000)
        let limiter = ProactiveRateLimiter(lastFires: [.idle: now])
        XCTAssertEqual(limiter.lastFires[.idle], now)
    }
}
