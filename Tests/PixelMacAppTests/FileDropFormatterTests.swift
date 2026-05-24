import XCTest

@testable import PixelMacApp

final class FileDropFormatterTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filedrop-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    // MARK: - Missing file

    func testNonExistentFileReturnsNil() {
        let ghost = tempDir.appendingPathComponent("ghost.swift")
        XCTAssertNil(FileDropFormatter.snippet(forFileURL: ghost))
    }

    // MARK: - Text file inline

    func testSwiftTextFileInlineCodeBlock() throws {
        let file = tempDir.appendingPathComponent("hello.swift")
        let body = "let x = 42\nprint(x)\n"
        try body.write(to: file, atomically: true, encoding: .utf8)

        let snippet = FileDropFormatter.snippet(forFileURL: file)
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("```swift"))
        XCTAssertTrue(snippet!.contains("// hello.swift"))
        XCTAssertTrue(snippet!.contains("let x = 42"))
        XCTAssertTrue(snippet!.hasSuffix("```\n"))
    }

    func testMarkdownFileInline() throws {
        let file = tempDir.appendingPathComponent("readme.md")
        try "# Hello\n\nworld\n".write(to: file, atomically: true, encoding: .utf8)
        let snippet = FileDropFormatter.snippet(forFileURL: file)
        XCTAssertTrue(snippet?.contains("```md") == true)
    }

    func testJSONFileInline() throws {
        let file = tempDir.appendingPathComponent("config.json")
        try #"{"key":"value"}"#.write(to: file, atomically: true, encoding: .utf8)
        let snippet = FileDropFormatter.snippet(forFileURL: file)
        XCTAssertTrue(snippet?.contains("```json") == true)
        XCTAssertTrue(snippet?.contains("// config.json") == true)
    }

    // MARK: - Large text file → path reference

    func testLargeTextFileReturnsPathReference() throws {
        let file = tempDir.appendingPathComponent("huge.txt")
        // 200KB content — over 100KB inline limit.
        let data = Data(repeating: 65, count: FileDropFormatter.maxInlineByteSize + 1)
        try data.write(to: file)

        let snippet = FileDropFormatter.snippet(forFileURL: file)
        XCTAssertTrue(snippet?.contains("📎") == true)
        XCTAssertTrue(snippet?.contains("huge.txt") == true)
        XCTAssertFalse(snippet?.contains("```") == true)
    }

    // MARK: - Binary file → path reference

    func testBinaryFileReturnsPathReference() throws {
        let file = tempDir.appendingPathComponent("image.png")
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try pngHeader.write(to: file)

        let snippet = FileDropFormatter.snippet(forFileURL: file)
        XCTAssertTrue(snippet?.contains("📎") == true)
        XCTAssertTrue(snippet?.contains("image.png") == true)
        XCTAssertFalse(snippet?.contains("```") == true)
    }

    // MARK: - Folder

    func testFolderReturnsListing() throws {
        // Manual create — tempDir zaten dizin.
        try "a".write(to: tempDir.appendingPathComponent("alpha.txt"),
                      atomically: true, encoding: .utf8)
        try "b".write(to: tempDir.appendingPathComponent("beta.swift"),
                      atomically: true, encoding: .utf8)

        let snippet = FileDropFormatter.snippet(forFileURL: tempDir)
        XCTAssertTrue(snippet?.contains("📁") == true)
        XCTAssertTrue(snippet?.contains("alpha.txt") == true)
        XCTAssertTrue(snippet?.contains("beta.swift") == true)
    }

    func testFolderTruncatesToMaxEntries() throws {
        // 25 dosya — 20 ile cap.
        for i in 1...25 {
            try "x".write(to: tempDir.appendingPathComponent("file\(i).txt"),
                          atomically: true, encoding: .utf8)
        }
        let snippet = FileDropFormatter.snippet(forFileURL: tempDir)
        XCTAssertTrue(snippet?.contains("ve 5 dosya daha") == true,
                      "Snippet: \(snippet ?? "nil")")
    }

    // MARK: - Text file extension whitelist

    func testTextFileExtensionWhitelistHasCommonLanguages() {
        let expected: [String] = ["swift", "py", "js", "ts", "rs", "go", "md", "json", "yaml"]
        for ext in expected {
            XCTAssertTrue(FileDropFormatter.isLikelyTextFile(extension: ext),
                          "Expected '.\(ext)' to be recognized as text")
        }
    }

    func testBinaryExtensionsNotInWhitelist() {
        for ext in ["png", "jpg", "exe", "zip", "mov", "mp3"] {
            XCTAssertFalse(FileDropFormatter.isLikelyTextFile(extension: ext),
                           "Expected '.\(ext)' NOT to be recognized as text")
        }
    }

    func testIsLikelyTextFileCaseInsensitive() {
        XCTAssertTrue(FileDropFormatter.isLikelyTextFile(extension: "SWIFT"))
        XCTAssertTrue(FileDropFormatter.isLikelyTextFile(extension: "JsOn"))
    }

    // MARK: - Code fence language aliases

    func testCodeFenceLanguageAliasing() {
        XCTAssertEqual(FileDropFormatter.codeFenceLanguage(forExtension: "yml"), "yaml")
        XCTAssertEqual(FileDropFormatter.codeFenceLanguage(forExtension: "js"), "javascript")
        XCTAssertEqual(FileDropFormatter.codeFenceLanguage(forExtension: "py"), "python")
        XCTAssertEqual(FileDropFormatter.codeFenceLanguage(forExtension: "rs"), "rust")
    }

    func testCodeFenceLanguageUnknownReturnsExtension() {
        // Bilinmeyen ama whitelist'te olabilir — extension olarak döner.
        XCTAssertEqual(FileDropFormatter.codeFenceLanguage(forExtension: "swift"), "swift")
        XCTAssertEqual(FileDropFormatter.codeFenceLanguage(forExtension: "json"), "json")
    }
}
