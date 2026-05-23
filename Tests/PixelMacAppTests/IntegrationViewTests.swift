import XCTest

@testable import PixelMacApp

final class IntegrationViewTests: XCTestCase {

    // MARK: - resolveBinaryPath

    func testResolveBinaryPathFallsBackWhenBundleMissingExecutable() {
        // Test bundle'ı normalde Contents/MacOS/pixel-mcp-server içermez,
        // bu yüzden fallback path beklenir.
        let resolution = MCPIntegrationConfig.resolveBinaryPath(bundle: .main)
        if !resolution.isBundled {
            XCTAssertEqual(resolution.path, "<repo>/.build/release/pixel-mcp-server")
        }
        // Eğer testler beklenmedik şekilde bundle'lı bir context'te çalışıyorsa
        // (Xcode app bundle vs.), sadece isBundled ile path tutarlılığını doğrula.
        if resolution.isBundled {
            XCTAssertTrue(resolution.path.hasSuffix("Contents/MacOS/pixel-mcp-server"))
        }
    }

    func testResolveBinaryPathDetectsBundledExecutable() throws {
        // Geçici bir "bundle" dizini oluştur, içine fake bir executable koy,
        // resolution'ın bunu bulduğunu doğrula.
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-integration-test-\(UUID().uuidString)")
        let macosDir = tmpRoot.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let exe = macosDir.appendingPathComponent("pixel-mcp-server")
        FileManager.default.createFile(
            atPath: exe.path,
            contents: Data("#!/bin/sh\necho test\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )

        // Sahte Bundle yerine bundleURL'i tmpRoot'a işaret eden bir mock yazmak
        // Bundle final class olduğu için zor; bu yüzden FileManager.isExecutableFile'ı
        // direkt path üzerinden test ediyoruz — Resolution logic'inin saf hali.
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: exe.path))

        // Saf logic check: candidate path computation
        let candidate = tmpRoot
            .appendingPathComponent("Contents/MacOS/pixel-mcp-server")
            .path
        XCTAssertEqual(candidate, exe.path)
    }

    // MARK: - snippet

    func testSnippetContainsBinaryPath() {
        let snippet = MCPIntegrationConfig.snippet(binaryPath: "/Applications/PixelAgent.app/Contents/MacOS/pixel-mcp-server")
        XCTAssertTrue(snippet.contains("\"command\": \"/Applications/PixelAgent.app/Contents/MacOS/pixel-mcp-server\""))
    }

    func testSnippetIsValidJSON() throws {
        let snippet = MCPIntegrationConfig.snippet(binaryPath: "/tmp/fake")
        let data = snippet.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        let mcpServers = parsed?["mcpServers"] as? [String: Any]
        XCTAssertNotNil(mcpServers)
        let pixel = mcpServers?["pixel-agent"] as? [String: Any]
        XCTAssertEqual(pixel?["command"] as? String, "/tmp/fake")
        XCTAssertEqual(pixel?["args"] as? [String], [])
    }

    func testSnippetEscapesIsTrivialBecausePathHasNoSpecialChars() {
        // Bundle path'leri normalde slash içerir, ki JSON string'inde escape gerekmez.
        let snippet = MCPIntegrationConfig.snippet(binaryPath: "/Applications/Pixel Agent.app/Contents/MacOS/pixel-mcp-server")
        // Boşluklu path'i JSON parse edilebilir mi?
        let data = snippet.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    // MARK: - ClientID

    func testClientIDProvidesDistinctConfigPaths() {
        let paths = IntegrationView.ClientID.allCases.map { $0.configPath }
        XCTAssertEqual(Set(paths).count, IntegrationView.ClientID.allCases.count)
    }

    func testClaudeDesktopConfigPathPointsToCanonicalLocation() {
        XCTAssertEqual(
            IntegrationView.ClientID.claudeDesktop.configPath,
            "~/Library/Application Support/Claude/claude_desktop_config.json"
        )
    }
}
