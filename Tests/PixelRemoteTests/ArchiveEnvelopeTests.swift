import XCTest
import PixelCore

@testable import PixelRemote

final class ArchiveEnvelopeTests: XCTestCase {

    // MARK: - ArchiveEntryPayload

    func testArchiveEntryPayloadCodableRoundTrip() throws {
        let original = ArchiveEntryPayload(
            id: "file:///tmp/archive/conversation-claude-2026-05-24T10-30-15Z.jsonl",
            backendKind: "claude",
            archivedAt: 1_716_540_615,
            messageCount: 12,
            firstUserSnippet: "Merhaba, bana yardım eder misin?"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArchiveEntryPayload.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testArchiveEntryPayloadNilSnippet() throws {
        let original = ArchiveEntryPayload(
            id: "file:///x.jsonl",
            backendKind: "gemini",
            archivedAt: 0,
            messageCount: 0,
            firstUserSnippet: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArchiveEntryPayload.self, from: data)
        XCTAssertNil(decoded.firstUserSnippet)
    }

    // MARK: - Envelope types in allCases

    func testArchiveEnvelopeTypesPresent() {
        let raws = Set(EnvelopeType.allCases.map(\.rawValue))
        XCTAssertTrue(raws.contains("archiveListRequest"))
        XCTAssertTrue(raws.contains("archiveListResponse"))
        XCTAssertTrue(raws.contains("archiveLoadRequest"))
        XCTAssertTrue(raws.contains("archiveLoadResponse"))
    }

    // MARK: - Factory methods

    func testArchiveListRequestEnvelope() {
        let env = RemoteEnvelope.archiveListRequest()
        XCTAssertEqual(env.type, .archiveListRequest)
        XCTAssertNil(env.payload)
    }

    func testArchiveListResponseEnvelope() {
        let entries = [
            ArchiveEntryPayload(id: "a", backendKind: "claude", archivedAt: 1, messageCount: 2, firstUserSnippet: "hi"),
            ArchiveEntryPayload(id: "b", backendKind: "codex", archivedAt: 2, messageCount: 3, firstUserSnippet: nil),
        ]
        let env = RemoteEnvelope.archiveListResponse(entries: entries)
        XCTAssertEqual(env.type, .archiveListResponse)
        XCTAssertEqual(env.payload?.archiveEntries?.count, 2)
        XCTAssertEqual(env.payload?.archiveEntries?.first?.id, "a")
    }

    func testArchiveLoadRequestEnvelope() {
        let env = RemoteEnvelope.archiveLoadRequest(id: "file:///x.jsonl")
        XCTAssertEqual(env.type, .archiveLoadRequest)
        XCTAssertEqual(env.payload?.archiveLoadID, "file:///x.jsonl")
    }

    func testArchiveLoadResponseEnvelope() {
        let messages = [
            Message(role: .user, text: "merhaba"),
            Message(role: .assistant, text: "selam"),
        ]
        let env = RemoteEnvelope.archiveLoadResponse(messages: messages)
        XCTAssertEqual(env.type, .archiveLoadResponse)
        XCTAssertEqual(env.payload?.archiveMessages?.count, 2)
        XCTAssertEqual(env.payload?.archiveMessages?.first?.text, "merhaba")
    }

    // MARK: - End-to-end envelope JSON round trip

    func testArchiveListResponseJSONRoundTrip() throws {
        let entries = [
            ArchiveEntryPayload(
                id: "file:///a.jsonl", backendKind: "claude",
                archivedAt: 100, messageCount: 5, firstUserSnippet: "test"
            ),
        ]
        let env = RemoteEnvelope.archiveListResponse(entries: entries)
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .archiveListResponse)
        XCTAssertEqual(decoded.payload?.archiveEntries, entries)
    }

    func testArchiveLoadResponseJSONRoundTrip() throws {
        // ISO8601 saniye precision — Message round-trip için açık date.
        let date = Date(timeIntervalSince1970: 1_716_540_615)
        let messages = [
            Message(id: UUID(), role: .user, text: "soru", createdAt: date),
            Message(id: UUID(), role: .assistant, text: "cevap", createdAt: date),
        ]
        let env = RemoteEnvelope.archiveLoadResponse(messages: messages)
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .archiveLoadResponse)
        XCTAssertEqual(decoded.payload?.archiveMessages?.count, 2)
        XCTAssertEqual(decoded.payload?.archiveMessages?.first?.text, "soru")
    }
}
