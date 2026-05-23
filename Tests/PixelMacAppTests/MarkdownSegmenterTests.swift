import XCTest

@testable import PixelMacApp

final class MarkdownSegmenterTests: XCTestCase {

    // MARK: - Boundary cases

    func testEmptyInputProducesNoSegments() {
        XCTAssertTrue(MarkdownSegmenter.segments(from: "").isEmpty)
    }

    func testPlainTextProducesSingleTextSegment() {
        let segments = MarkdownSegmenter.segments(from: "Hello world.")
        XCTAssertEqual(segments, [.text("Hello world.")])
    }

    func testMultilineTextProducesSingleTextSegment() {
        let input = "Line one.\nLine two.\nLine three."
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.text(input)])
    }

    // MARK: - Code block detection

    func testSingleCodeBlockWithLanguage() {
        let input = """
        Here is some Swift:
        ```swift
        let x = 1
        let y = 2
        ```
        That's it.
        """
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], .text("Here is some Swift:"))
        XCTAssertEqual(segments[1], .codeBlock(content: "let x = 1\nlet y = 2", language: "swift"))
        XCTAssertEqual(segments[2], .text("That's it."))
    }

    func testCodeBlockWithoutLanguage() {
        let input = """
        ```
        plain code
        ```
        """
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.codeBlock(content: "plain code", language: nil)])
    }

    func testMultipleCodeBlocks() {
        let input = """
        First:
        ```python
        print("a")
        ```
        Second:
        ```bash
        echo b
        ```
        Done.
        """
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments.count, 5)
        XCTAssertEqual(segments[0], .text("First:"))
        XCTAssertEqual(segments[1], .codeBlock(content: "print(\"a\")", language: "python"))
        XCTAssertEqual(segments[2], .text("Second:"))
        XCTAssertEqual(segments[3], .codeBlock(content: "echo b", language: "bash"))
        XCTAssertEqual(segments[4], .text("Done."))
    }

    func testEmptyCodeBlockEmitsEmptyContent() {
        let input = "```\n```"
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.codeBlock(content: "", language: nil)])
    }

    // MARK: - Streaming (unclosed fences)

    func testUnclosedCodeBlockIsEmittedAsCodeBlock() {
        // Streaming sırasında kullanıcı kapatma fence'ini henüz görmedi.
        let input = """
        Streaming partial:
        ```swift
        let x = 1
        let y =
        """
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0], .text("Streaming partial:"))
        XCTAssertEqual(segments[1], .codeBlock(content: "let x = 1\nlet y =", language: "swift"))
    }

    func testJustOpenedFenceProducesEmptyCodeBlock() {
        // İlk token'lar henüz akıyor; opening fence geldi ama içerik yok.
        let input = "```swift"
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.codeBlock(content: "", language: "swift")])
    }

    // MARK: - Language tag parsing

    func testLanguageTagIsTrimmed() {
        let input = "```   rust   \nfn main() {}\n```"
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.codeBlock(content: "fn main() {}", language: "rust")])
    }

    func testLanguageTagAllowsHyphen() {
        // "objective-c", "shell-session" gibi etiketler korunmalı.
        let input = "```objective-c\nNSLog(@\"hi\");\n```"
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.codeBlock(content: "NSLog(@\"hi\");", language: "objective-c")])
    }

    // MARK: - Inline backticks (not fences)

    func testInlineBackticksDoNotTriggerFence() {
        // Tek backtick veya satır içinde ``` (sat başında değil) inline kalır.
        let input = "Use `let x = 1` to bind. Then call ```foo``` (still inline)."
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments, [.text(input)])
    }

    // MARK: - Whitespace handling

    func testTextSegmentsPreserveInternalBlankLines() {
        let input = "Paragraph one.\n\nParagraph two.\n\n```\ncode\n```\nEnd."
        let segments = MarkdownSegmenter.segments(from: input)
        XCTAssertEqual(segments.count, 3)
        if case .text(let first) = segments[0] {
            XCTAssertTrue(first.contains("Paragraph one."))
            XCTAssertTrue(first.contains("Paragraph two."))
        } else {
            XCTFail("İlk segment text olmalı")
        }
        XCTAssertEqual(segments[1], .codeBlock(content: "code", language: nil))
        XCTAssertEqual(segments[2], .text("End."))
    }

    // MARK: - MessageSegment Equatable

    func testMessageSegmentEquatable() {
        XCTAssertEqual(MessageSegment.text("a"), MessageSegment.text("a"))
        XCTAssertNotEqual(MessageSegment.text("a"), MessageSegment.text("b"))
        XCTAssertEqual(
            MessageSegment.codeBlock(content: "x", language: "swift"),
            MessageSegment.codeBlock(content: "x", language: "swift")
        )
        XCTAssertNotEqual(
            MessageSegment.codeBlock(content: "x", language: "swift"),
            MessageSegment.codeBlock(content: "x", language: nil)
        )
    }
}
