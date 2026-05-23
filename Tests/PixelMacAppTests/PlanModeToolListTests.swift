import XCTest
import PixelBackends

@testable import PixelMacApp

final class PlanModeToolListTests: XCTestCase {

    // MARK: - Catalog integrity

    func testCatalogIsNonEmpty() {
        XCTAssertFalse(PlanModeToolCatalog.tools.isEmpty)
    }

    func testCatalogIDsAreUnique() {
        let ids = PlanModeToolCatalog.tools.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate tool ID'leri var")
    }

    func testCatalogNamesAreUnique() {
        let names = PlanModeToolCatalog.tools.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Duplicate tool isimleri var")
    }

    func testCatalogHasBothAllowedAndBlocked() {
        XCTAssertFalse(PlanModeToolCatalog.allowedTools.isEmpty)
        XCTAssertFalse(PlanModeToolCatalog.blockedTools.isEmpty)
    }

    func testAllowedAndBlockedPartitionTheCatalog() {
        let allowed = PlanModeToolCatalog.allowedTools
        let blocked = PlanModeToolCatalog.blockedTools
        XCTAssertEqual(
            allowed.count + blocked.count,
            PlanModeToolCatalog.tools.count
        )
        XCTAssertTrue(allowed.allSatisfy { $0.allowed })
        XCTAssertTrue(blocked.allSatisfy { !$0.allowed })
    }

    func testEveryToolHasNonEmptyMetadata() {
        for tool in PlanModeToolCatalog.tools {
            XCTAssertFalse(tool.id.isEmpty, "ID boş: \(tool)")
            XCTAssertFalse(tool.name.isEmpty, "İsim boş: \(tool.id)")
            XCTAssertFalse(tool.summary.isEmpty, "Özet boş: \(tool.id)")
        }
    }

    // MARK: - Demo coverage (regression guard)

    /// Sprint 1 demo senaryosu Plan paneli için "Read ✓ / Glob ✓ / Edit ✗ / Bash ✗"
    /// göreceğini söyler — bu 4 ID'nin catalog'da doğru tarafta olduğunu sabitler.
    func testDemoScenarioToolsArePresent() {
        let byID = Dictionary(uniqueKeysWithValues: PlanModeToolCatalog.tools.map { ($0.id, $0) })

        XCTAssertEqual(byID["read"]?.allowed, true)
        XCTAssertEqual(byID["glob"]?.allowed, true)
        XCTAssertEqual(byID["edit"]?.allowed, false)
        XCTAssertEqual(byID["bash"]?.allowed, false)
    }

    // MARK: - Backend support

    func testClaudeSupportsPlanMode() {
        XCTAssertTrue(PlanModeToolCatalog.supportsPlanMode(kind: .claude))
    }

    func testCodexAndGeminiDoNotSupportPlanMode() {
        XCTAssertFalse(PlanModeToolCatalog.supportsPlanMode(kind: .codex))
        XCTAssertFalse(PlanModeToolCatalog.supportsPlanMode(kind: .gemini))
    }

    // MARK: - PlanModeTool Equatable

    func testToolEquatableMatchesID() {
        let lhs = PlanModeTool(id: "x", name: "X", summary: "x", allowed: true)
        let rhs = PlanModeTool(id: "x", name: "X", summary: "x", allowed: true)
        let other = PlanModeTool(id: "y", name: "X", summary: "x", allowed: true)
        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, other)
    }
}
