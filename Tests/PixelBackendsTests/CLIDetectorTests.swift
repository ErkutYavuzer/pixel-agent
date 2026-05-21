import XCTest

@testable import PixelBackends

final class CLIDetectorTests: XCTestCase {
    func testCLIKindRawValues() {
        XCTAssertEqual(CLIKind.claude.rawValue, "claude")
        XCTAssertEqual(CLIKind.codex.rawValue, "codex")
        XCTAssertEqual(CLIKind.gemini.rawValue, "gemini")
    }

    func testCLIKindExecutableName() {
        for kind in CLIKind.allCases {
            XCTAssertEqual(kind.executableName, kind.rawValue)
        }
    }

    func testCLIKindDisplayNames() {
        XCTAssertEqual(CLIKind.claude.displayName, "Claude")
        XCTAssertEqual(CLIKind.codex.displayName, "Codex")
        XCTAssertEqual(CLIKind.gemini.displayName, "Gemini")
    }

    func testAllCasesContainsAllThree() {
        XCTAssertEqual(CLIKind.allCases.count, 3)
        XCTAssertTrue(CLIKind.allCases.contains(.claude))
        XCTAssertTrue(CLIKind.allCases.contains(.codex))
        XCTAssertTrue(CLIKind.allCases.contains(.gemini))
    }

    func testLocateReturnsTypeOfStringOrNil() {
        let detector = CLIDetector()
        for kind in CLIKind.allCases {
            let result = detector.locate(kind)
            if let path = result {
                XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path),
                              "\(kind) için döndürülen path executable olmalı: \(path)")
            }
        }
    }

    func testAvailableSubsetOfAllCases() {
        let detector = CLIDetector()
        let available = detector.available()
        for kind in available.keys {
            XCTAssertTrue(CLIKind.allCases.contains(kind))
        }
    }
}
