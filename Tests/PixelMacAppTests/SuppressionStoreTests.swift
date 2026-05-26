import XCTest
@testable import PixelMacApp

/// **Sprint 38 (v0.2.65):** SuppressionStore CRUD + persist testleri.
final class SuppressionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.suppression.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEmptyStoreNothingSuppressed() {
        let store = SuppressionStore()
        XCTAssertFalse(store.shouldSuppress(.idle(minutes: 10)))
        XCTAssertFalse(store.shouldSuppress(.appChanged(name: "X", bundleID: "com.x")))
    }

    func testKindSuppressionBlocksTrigger() {
        var store = SuppressionStore()
        store.setKind(.idle, suppressed: true)
        XCTAssertTrue(store.shouldSuppress(.idle(minutes: 30)))
        XCTAssertFalse(store.shouldSuppress(.appChanged(name: "X", bundleID: "com.x")))
    }

    func testBundleSuppressionBlocksOnlyThatBundle() {
        var store = SuppressionStore()
        store.setBundle("com.apple.Safari", suppressed: true)
        XCTAssertTrue(store.shouldSuppress(.appChanged(name: "Safari", bundleID: "com.apple.Safari")))
        XCTAssertFalse(store.shouldSuppress(.appChanged(name: "Slack", bundleID: "com.tinyspeck.slack")))
    }

    func testBundleNormalization() {
        var store = SuppressionStore()
        store.setBundle("  COM.Apple.Safari  ", suppressed: true)
        // Lowercase + trim normalize → match olur
        XCTAssertTrue(store.shouldSuppress(.appChanged(name: "Safari", bundleID: "com.apple.safari")))
    }

    func testSetKindFalseRemoves() {
        var store = SuppressionStore()
        store.setKind(.idle, suppressed: true)
        XCTAssertTrue(store.shouldSuppress(.idle(minutes: 1)))
        store.setKind(.idle, suppressed: false)
        XCTAssertFalse(store.shouldSuppress(.idle(minutes: 1)))
    }

    func testSetBundleFalseRemoves() {
        var store = SuppressionStore()
        store.setBundle("com.apple.Safari", suppressed: true)
        store.setBundle("com.apple.Safari", suppressed: false)
        XCTAssertFalse(store.shouldSuppress(.appChanged(name: "Safari", bundleID: "com.apple.Safari")))
    }

    func testRoundTripUserDefaults() {
        var store = SuppressionStore()
        store.setKind(.appChange, suppressed: true)
        store.setBundle("com.apple.dt.Xcode", suppressed: true)
        store.save(to: defaults)

        let loaded = SuppressionStore.load(from: defaults)
        XCTAssertEqual(loaded.suppressedKinds, [.appChange])
        XCTAssertEqual(loaded.suppressedBundles, ["com.apple.dt.xcode"])
    }

    func testLoadFromCorruptDefaultsReturnsEmpty() {
        defaults.set("not an array", forKey: SuppressionStore.suppressedKindsDefaultsKey)
        let loaded = SuppressionStore.load(from: defaults)
        XCTAssertTrue(loaded.suppressedKinds.isEmpty)
        XCTAssertTrue(loaded.suppressedBundles.isEmpty)
    }

    func testIdleNotAffectedByBundleSuppression() {
        var store = SuppressionStore()
        store.setBundle("com.apple.Safari", suppressed: true)
        // Idle bundle'a bağlı değil — suppress edilmemeli
        XCTAssertFalse(store.shouldSuppress(.idle(minutes: 20)))
    }
}
