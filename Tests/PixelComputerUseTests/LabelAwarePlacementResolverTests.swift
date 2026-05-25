import XCTest

@testable import PixelComputerUse

final class LabelAwarePlacementResolverTests: XCTestCase {

    // MARK: - Button family → topRightOutside

    func testButtonResolvesToTopRightOutside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXButton"), .topRightOutside)
    }

    func testMenuItemResolvesToTopRightOutside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXMenuItem"), .topRightOutside)
    }

    func testCheckBoxResolvesToTopRightOutside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXCheckBox"), .topRightOutside)
    }

    func testRadioButtonResolvesToTopRightOutside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXRadioButton"), .topRightOutside)
    }

    // MARK: - Text-leading family → topRightInside

    func testLinkResolvesToTopRightInside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXLink"), .topRightInside)
    }

    func testTextFieldResolvesToTopRightInside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXTextField"), .topRightInside)
    }

    func testTextAreaResolvesToTopRightInside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXTextArea"), .topRightInside)
    }

    func testPopUpButtonResolvesToTopRightInside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXPopUpButton"), .topRightInside)
    }

    func testComboBoxResolvesToTopRightInside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXComboBox"), .topRightInside)
    }

    // MARK: - Unknown / decorative → topLeftOutside fallback

    func testUnknownRoleFallsBackToTopLeftOutside() {
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXUnknown"), .topLeftOutside)
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXImage"), .topLeftOutside)
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: "AXGroup"), .topLeftOutside)
        XCTAssertEqual(LabelAwarePlacementResolver.placement(for: ""), .topLeftOutside)
    }

    // MARK: - SoMOptions / BadgePlacement enum coverage

    func testBadgePlacementLabelAwareIsCodable() throws {
        let original = SoMOptions(badgePlacement: .labelAware)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoMOptions.self, from: data)
        XCTAssertEqual(decoded.badgePlacement, .labelAware)
    }

    func testBadgePlacementRawValueLabelAware() {
        XCTAssertEqual(BadgePlacement.labelAware.rawValue, "labelAware")
    }

    func testAllInteractiveRolesHaveDistinctPlacement() {
        // Interactive roles set (AXRole.interactiveRoles, v0.2.38) için
        // her birinin placement'ı belirli (default'a düşmüyor — heuristic
        // anlamlı).
        let interactiveRoles = [
            "AXButton", "AXLink", "AXTextField", "AXTextArea",
            "AXCheckBox", "AXRadioButton", "AXPopUpButton",
            "AXComboBox", "AXMenuItem",
        ]
        for role in interactiveRoles {
            let placement = LabelAwarePlacementResolver.placement(for: role)
            XCTAssertNotEqual(placement, .topLeftOutside,
                "\(role) için label-aware placement default'a düşmemeli")
        }
    }
}
