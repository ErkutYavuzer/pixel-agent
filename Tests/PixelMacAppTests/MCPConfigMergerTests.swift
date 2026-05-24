import XCTest

@testable import PixelMacApp

final class MCPConfigMergerTests: XCTestCase {

    private let binaryPath = "/Applications/PixelAgent.app/Contents/MacOS/pixel-mcp-server"

    // MARK: - Merge from empty / nil

    func testMergeIntoNilProducesFreshConfig() throws {
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: nil
        )
        let parsed = try JSONSerialization.jsonObject(with: merged.data(using: .utf8)!)
            as! [String: Any]
        let mcpServers = parsed["mcpServers"] as! [String: Any]
        let pixel = mcpServers["pixel-agent"] as! [String: Any]
        XCTAssertEqual(pixel["command"] as? String, binaryPath)
        XCTAssertEqual(pixel["args"] as? [String], [])
    }

    func testMergeIntoEmptyStringProducesFreshConfig() throws {
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: ""
        )
        XCTAssertTrue(merged.contains("pixel-agent"))
        XCTAssertTrue(merged.contains(binaryPath))
    }

    // MARK: - Merge preserves other entries

    func testMergePreservesOtherMCPServers() throws {
        let existing = """
        {
          "mcpServers": {
            "other-server": {
              "command": "/usr/bin/other",
              "args": ["--foo"]
            }
          }
        }
        """
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: existing
        )
        let parsed = try JSONSerialization.jsonObject(with: merged.data(using: .utf8)!)
            as! [String: Any]
        let mcpServers = parsed["mcpServers"] as! [String: Any]
        XCTAssertNotNil(mcpServers["other-server"])
        XCTAssertNotNil(mcpServers["pixel-agent"])
        let other = mcpServers["other-server"] as! [String: Any]
        XCTAssertEqual(other["command"] as? String, "/usr/bin/other")
    }

    func testMergePreservesTopLevelSiblings() throws {
        let existing = """
        {
          "theme": "dark",
          "mcpServers": {}
        }
        """
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: existing
        )
        let parsed = try JSONSerialization.jsonObject(with: merged.data(using: .utf8)!)
            as! [String: Any]
        XCTAssertEqual(parsed["theme"] as? String, "dark")
    }

    func testMergeWithoutMcpServersKeyCreatesIt() throws {
        let existing = """
        {
          "theme": "dark"
        }
        """
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: existing
        )
        let parsed = try JSONSerialization.jsonObject(with: merged.data(using: .utf8)!)
            as! [String: Any]
        XCTAssertNotNil(parsed["mcpServers"])
        XCTAssertEqual(parsed["theme"] as? String, "dark")
    }

    // MARK: - Merge overwrites existing pixel-agent entry

    func testMergeOverwritesExistingPixelAgentEntry() throws {
        let existing = """
        {
          "mcpServers": {
            "pixel-agent": {
              "command": "/old/path/pixel-mcp-server",
              "args": ["legacy"]
            }
          }
        }
        """
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: existing
        )
        let parsed = try JSONSerialization.jsonObject(with: merged.data(using: .utf8)!)
            as! [String: Any]
        let mcpServers = parsed["mcpServers"] as! [String: Any]
        let pixel = mcpServers["pixel-agent"] as! [String: Any]
        XCTAssertEqual(pixel["command"] as? String, binaryPath)
        XCTAssertEqual(pixel["args"] as? [String], [])
    }

    // MARK: - Output is pretty-printed JSON

    func testMergedOutputIsPrettyPrinted() throws {
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: nil
        )
        XCTAssertTrue(merged.contains("\n"))
        XCTAssertTrue(merged.contains("  "))
    }

    func testMergedOutputIsParseableJSON() throws {
        let merged = try MCPConfigMerger.mergePixelAgent(
            binaryPath: binaryPath,
            intoExistingJSON: nil
        )
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: merged.data(using: .utf8)!)
        )
    }

    // MARK: - Parse errors

    func testInvalidJSONThrowsParseError() {
        XCTAssertThrowsError(
            try MCPConfigMerger.mergePixelAgent(
                binaryPath: binaryPath,
                intoExistingJSON: "this is not JSON {{{"
            )
        ) { error in
            guard case MCPConfigError.parseFailed = error else {
                return XCTFail("Beklenen .parseFailed; got \(error)")
            }
        }
    }

    func testNonObjectRootJSONThrows() {
        XCTAssertThrowsError(
            try MCPConfigMerger.mergePixelAgent(
                binaryPath: binaryPath,
                intoExistingJSON: "[1, 2, 3]"
            )
        )
    }

    // MARK: - currentStatus

    func testStatusOfMissingConfig() {
        XCTAssertEqual(
            MCPConfigMerger.currentStatus(existingJSON: nil, binaryPath: binaryPath),
            .notConfigured
        )
        XCTAssertEqual(
            MCPConfigMerger.currentStatus(existingJSON: "", binaryPath: binaryPath),
            .notConfigured
        )
    }

    func testStatusOfConfigWithoutPixelAgent() {
        let existing = """
        {"mcpServers": {"other": {"command": "/x", "args": []}}}
        """
        XCTAssertEqual(
            MCPConfigMerger.currentStatus(existingJSON: existing, binaryPath: binaryPath),
            .notConfigured
        )
    }

    func testStatusOfCorrectlyConfiguredPixelAgent() {
        let existing = """
        {
          "mcpServers": {
            "pixel-agent": {
              "command": "\(binaryPath)",
              "args": []
            }
          }
        }
        """
        XCTAssertEqual(
            MCPConfigMerger.currentStatus(existingJSON: existing, binaryPath: binaryPath),
            .configuredCorrectly
        )
    }

    func testStatusOfStaleBinaryPath() {
        let stalePath = "/old/path/pixel-mcp-server"
        let existing = """
        {
          "mcpServers": {
            "pixel-agent": {"command": "\(stalePath)", "args": []}
          }
        }
        """
        XCTAssertEqual(
            MCPConfigMerger.currentStatus(existingJSON: existing, binaryPath: binaryPath),
            .configuredWithDifferentPath(currentPath: stalePath)
        )
    }

    // MARK: - Status enum metadata

    func testStatusActionLabels() {
        XCTAssertEqual(MCPConfigStatus.notConfigured.actionLabel, "Kur")
        XCTAssertEqual(MCPConfigStatus.configuredCorrectly.actionLabel, "Yeniden Uygula")
        XCTAssertEqual(
            MCPConfigStatus.configuredWithDifferentPath(currentPath: "/x").actionLabel,
            "Güncelle"
        )
    }

    func testStatusDisplayNamesUnique() {
        let names = [
            MCPConfigStatus.notConfigured.displayName,
            MCPConfigStatus.configuredCorrectly.displayName,
            MCPConfigStatus.configuredWithDifferentPath(currentPath: "/x").displayName,
        ]
        XCTAssertEqual(Set(names).count, names.count)
    }
}
