import XCTest
import PixelBackends
import PixelSubagent

@testable import PixelMacApp

final class SubagentMessageFormatterTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        backend: CLIKind = .gemini,
        result: SubagentResult? = nil,
        partial: String = "",
        status: SubagentStatus = .completed
    ) -> SubagentSession {
        SubagentSession(
            prompt: "test prompt",
            backendKind: backend,
            budget: .default,
            status: status,
            startedAt: Date(),
            finishedAt: Date(),
            result: result,
            partialOutput: partial
        )
    }

    // MARK: - Completed

    func testCompletedRendersSonucPrefix() {
        let session = makeSession(
            backend: .gemini,
            result: .completed(output: "Bu özet ...", durationSeconds: 1.2)
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent gemini] sonuç:\nBu özet ...")
    }

    func testCompletedTrimsWhitespace() {
        let session = makeSession(
            backend: .claude,
            result: .completed(output: "  cevap  \n", durationSeconds: 0.5)
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent claude] sonuç:\ncevap")
    }

    // MARK: - Cancelled

    func testCancelledWithoutPartialJustSaysCancelled() {
        let session = makeSession(
            result: .cancelled(partialOutput: "", durationSeconds: 0.1),
            status: .cancelled
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent gemini] iptal edildi.")
    }

    func testCancelledWithPartialIncludesIt() {
        let session = makeSession(
            backend: .codex,
            result: .cancelled(partialOutput: "yarım", durationSeconds: 0.3),
            status: .cancelled
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent codex] iptal edildi. Kısmi çıktı:\nyarım")
    }

    // MARK: - Budget exceeded

    func testBudgetExceededDurationReason() {
        let session = makeSession(
            backend: .claude,
            result: .budgetExceeded(reason: .duration, partialOutput: "", durationSeconds: 10),
            status: .budgetExceeded(.duration)
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent claude] bütçe aşıldı (süre aşıldı).")
    }

    func testBudgetExceededOutputBytesReasonWithPartial() {
        let session = makeSession(
            backend: .gemini,
            result: .budgetExceeded(reason: .outputBytes, partialOutput: "uzun ...", durationSeconds: 5),
            status: .budgetExceeded(.outputBytes)
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(
            text,
            "[subagent gemini] bütçe aşıldı (çıktı boyutu aşıldı). Kısmi çıktı:\nuzun ..."
        )
    }

    // MARK: - Failed

    func testFailedWithoutPartial() {
        let session = makeSession(
            backend: .codex,
            result: .failed(error: "exit 1", partialOutput: "", durationSeconds: 0.4),
            status: .failed(error: "exit 1")
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent codex] hata: exit 1")
    }

    func testFailedWithPartial() {
        let session = makeSession(
            backend: .gemini,
            result: .failed(error: "parse fail", partialOutput: "yarım", durationSeconds: 0.4),
            status: .failed(error: "parse fail")
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertEqual(text, "[subagent gemini] hata: parse fail\nKısmi çıktı:\nyarım")
    }

    // MARK: - Defensive

    func testNoResultFallsBackToStatusLabel() {
        // Defensive: terminal değilse veya result set edilmediyse (gerçekleşmez
        // ama yine de) status displayLabel'ını döndür.
        let session = makeSession(result: nil, status: .running)
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertTrue(text.hasPrefix("[subagent gemini] durum:"))
        XCTAssertTrue(text.contains("Çalışıyor"))
    }

    // MARK: - Backend prefix

    func testPrefixUsesRawValueNotDisplayName() {
        // rawValue lowercase tutarlı: [subagent gemini] vs [subagent Gemini].
        // Demo senaryosu lowercase yazıyor; tüketici fonksiyonlar (logging,
        // markdown) için case-stable input istiyoruz.
        let session = makeSession(
            backend: .claude,
            result: .completed(output: "x", durationSeconds: 1)
        )
        let text = SubagentMessageFormatter.format(session: session)
        XCTAssertTrue(text.hasPrefix("[subagent claude]"))
    }
}
