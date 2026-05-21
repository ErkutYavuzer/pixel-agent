import XCTest

@testable import PixelMascot

final class MascotStateTests: XCTestCase {
    func testAllCasesContainsFour() {
        XCTAssertEqual(MascotState.allCases.count, 4)
        XCTAssertTrue(MascotState.allCases.contains(.idle))
        XCTAssertTrue(MascotState.allCases.contains(.thinking))
        XCTAssertTrue(MascotState.allCases.contains(.speaking))
        XCTAssertTrue(MascotState.allCases.contains(.error))
    }

    func testRawValues() {
        XCTAssertEqual(MascotState.idle.rawValue, "idle")
        XCTAssertEqual(MascotState.thinking.rawValue, "thinking")
        XCTAssertEqual(MascotState.speaking.rawValue, "speaking")
        XCTAssertEqual(MascotState.error.rawValue, "error")
    }
}
