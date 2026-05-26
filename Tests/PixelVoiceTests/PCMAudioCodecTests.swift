import XCTest
@testable import PixelVoice

/// **Sprint 43 (v0.2.70):** PCMAudioCodec round-trip + edge case tests.
final class PCMAudioCodecTests: XCTestCase {

    func testEncodeEmptyReturnsEmpty() {
        XCTAssertEqual(PCMAudioCodec.encodeToBase64([]), "")
    }

    func testDecodeEmptyReturnsEmpty() {
        XCTAssertTrue(PCMAudioCodec.decodeFromBase64("").isEmpty)
    }

    func testDecodeCorruptReturnsEmpty() {
        XCTAssertTrue(PCMAudioCodec.decodeFromBase64("this is not base64!").isEmpty)
    }

    func testRoundTripSingleSample() {
        let original: [Int16] = [12345]
        let encoded = PCMAudioCodec.encodeToBase64(original)
        let decoded = PCMAudioCodec.decodeFromBase64(encoded)
        XCTAssertEqual(decoded, original)
    }

    func testRoundTripMultipleSamples() {
        let original: [Int16] = [-32768, -1000, 0, 500, 32767]
        let encoded = PCMAudioCodec.encodeToBase64(original)
        let decoded = PCMAudioCodec.decodeFromBase64(encoded)
        XCTAssertEqual(decoded, original)
    }

    func testRoundTripLargeBuffer() {
        let original = (0..<24000).map { Int16($0 % 32767) }
        let encoded = PCMAudioCodec.encodeToBase64(original)
        let decoded = PCMAudioCodec.decodeFromBase64(encoded)
        XCTAssertEqual(decoded.count, 24000)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Float ↔ Int16 conversion

    func testFloat32ToInt16Range() {
        XCTAssertEqual(PCMAudioCodec.float32ToInt16([-1.0]), [-32767])
        XCTAssertEqual(PCMAudioCodec.float32ToInt16([0.0]), [0])
        XCTAssertEqual(PCMAudioCodec.float32ToInt16([1.0]), [32767])
    }

    func testFloat32ToInt16Clamps() {
        XCTAssertEqual(PCMAudioCodec.float32ToInt16([-2.0]), [-32767])
        XCTAssertEqual(PCMAudioCodec.float32ToInt16([2.5]), [32767])
    }

    func testInt16ToFloat32Range() {
        let result = PCMAudioCodec.int16ToFloat32([0])
        XCTAssertEqual(result.first ?? -1, 0.0 as Float, accuracy: Float(0.0001))
    }

    func testInt16ToFloat32Max() {
        let result = PCMAudioCodec.int16ToFloat32([32767])
        XCTAssertEqual(result.first ?? 0, 1.0 as Float, accuracy: Float(0.0001))
    }

    func testFloat32Int16RoundTripPreservesSign() {
        let floats: [Float] = [0.5, -0.5]
        let ints = PCMAudioCodec.float32ToInt16(floats)
        let back = PCMAudioCodec.int16ToFloat32(ints)
        XCTAssertEqual(back[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(back[1], -0.5, accuracy: 0.001)
    }

    // MARK: - Constants regression

    func testSampleRateIs24kHz() {
        XCTAssertEqual(PCMAudioCodec.sampleRate, 24_000)
    }

    func testChannelsIsMono() {
        XCTAssertEqual(PCMAudioCodec.channels, 1)
    }

    func testBytesPerSample() {
        XCTAssertEqual(PCMAudioCodec.bytesPerSample, 2)
    }
}
