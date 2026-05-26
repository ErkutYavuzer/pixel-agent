import XCTest
@testable import PixelVoice

/// **Sprint 43 (v0.2.70):** RealtimeEventCodec encode + decode testleri.
final class RealtimeEventTests: XCTestCase {

    // MARK: - Client → Server encode

    func testSessionUpdateEncode() throws {
        let config = SessionConfig()
        let event = RealtimeClientEvent.sessionUpdate(config: config)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "session.update")
        XCTAssertNotNil(json["session"])
    }

    func testAudioBufferAppendEncode() throws {
        let event = RealtimeClientEvent.inputAudioBufferAppend(audioBase64: "AAAB")
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(json["audio"] as? String, "AAAB")
    }

    func testAudioBufferCommitEncode() throws {
        let event = RealtimeClientEvent.inputAudioBufferCommit
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "input_audio_buffer.commit")
    }

    func testResponseCreateEncode() throws {
        let event = RealtimeClientEvent.responseCreate
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "response.create")
    }

    func testResponseCancelEncode() throws {
        let event = RealtimeClientEvent.responseCancel
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "response.cancel")
    }

    // MARK: - SessionConfig fields

    func testSessionConfigDefaultModalities() throws {
        let config = SessionConfig()
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modalities = json["modalities"] as? [String]
        XCTAssertEqual(modalities, ["text", "audio"])
    }

    func testSessionConfigDefaultVoice() throws {
        let config = SessionConfig()
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["voice"] as? String, "alloy")
    }

    func testSessionConfigPCM16Format() throws {
        let config = SessionConfig()
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["input_audio_format"] as? String, "pcm16")
        XCTAssertEqual(json["output_audio_format"] as? String, "pcm16")
    }

    func testTurnDetectionServerVADDefault() throws {
        let config = SessionConfig()
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let td = json["turn_detection"] as? [String: Any]
        XCTAssertEqual(td?["type"] as? String, "server_vad")
        XCTAssertEqual(td?["threshold"] as? Double, 0.5)
        XCTAssertEqual(td?["silence_duration_ms"] as? Int, 500)
    }

    // MARK: - Server → Client decode

    func testDecodeSessionCreated() {
        let json = #"{"type":"session.created","session":{"id":"sess_abc"}}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .sessionCreated(sessionID: "sess_abc"))
    }

    func testDecodeAudioDelta() {
        let json = #"{"type":"response.audio.delta","delta":"AAAB"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .audioDelta(base64: "AAAB"))
    }

    func testDecodeTranscriptDelta() {
        let json = #"{"type":"response.audio_transcript.delta","delta":"Merhaba"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .transcriptDelta(text: "Merhaba"))
    }

    func testDecodeResponseDone() {
        let json = #"{"type":"response.done"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .responseDone)
    }

    func testDecodeSpeechStarted() {
        let json = #"{"type":"input_audio_buffer.speech_started"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .speechStarted)
    }

    func testDecodeError() {
        let json = #"{"type":"error","error":{"message":"Invalid API key"}}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .error(message: "Invalid API key"))
    }

    func testDecodeUnknownType() {
        let json = #"{"type":"future.event.type"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .unknown(type: "future.event.type"))
    }

    func testDecodeCorruptJSONReturnsNil() {
        let event = RealtimeServerEvent.decode(Data("not json".utf8))
        XCTAssertNil(event)
    }

    func testDecodeMissingTypeReturnsNil() {
        let json = #"{"foo":"bar"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertNil(event)
    }
}
