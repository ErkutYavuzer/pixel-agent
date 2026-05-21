import XCTest

@testable import PixelTools

final class DockBadgeTests: XCTestCase {
    @MainActor
    func testAPISurfaceDoesNotCrash() {
        DockBadge.clear()
        DockBadge.set(nil)
        DockBadge.set("1")
        DockBadge.set("!")
        DockBadge.setCount(0)
        DockBadge.setCount(5)
        DockBadge.setCount(-1)
        DockBadge.clear()
    }
}
