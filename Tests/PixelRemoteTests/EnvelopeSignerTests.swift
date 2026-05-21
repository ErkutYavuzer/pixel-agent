import XCTest
import CryptoKit
@testable import PixelRemote

final class EnvelopeSignerTests: XCTestCase {
    private var key: Curve25519.Signing.PrivateKey!

    override func setUp() {
        super.setUp()
        key = Curve25519.Signing.PrivateKey()
    }

    func testSignAndVerifyRoundTrip() throws {
        let envelope = RemoteEnvelope.userMessage(text: "Merhaba")
        let signed = try EnvelopeSigner.sign(envelope, with: key)
        XCTAssertNotNil(signed.sig)
        XCTAssertTrue(EnvelopeSigner.verify(signed, with: key.publicKey))
    }

    func testVerifyFailsForTamperedPayload() throws {
        let original = RemoteEnvelope.userMessage(text: "Merhaba")
        let signed = try EnvelopeSigner.sign(original, with: key)
        let tampered = RemoteEnvelope(
            v: signed.v,
            id: signed.id,
            ts: signed.ts,
            type: signed.type,
            payload: EnvelopePayload(text: "Sahte", role: "user"),
            sig: signed.sig
        )
        XCTAssertFalse(EnvelopeSigner.verify(tampered, with: key.publicKey))
    }

    func testVerifyFailsForWrongPublicKey() throws {
        let envelope = RemoteEnvelope.ping()
        let signed = try EnvelopeSigner.sign(envelope, with: key)
        let otherKey = Curve25519.Signing.PrivateKey()
        XCTAssertFalse(EnvelopeSigner.verify(signed, with: otherKey.publicKey))
    }

    func testVerifyFailsWhenSignatureMissing() {
        let envelope = RemoteEnvelope.ping()
        XCTAssertNil(envelope.sig)
        XCTAssertFalse(EnvelopeSigner.verify(envelope, with: key.publicKey))
    }

    func testVerifyFailsForCorruptBase64() throws {
        let signed = try EnvelopeSigner.sign(RemoteEnvelope.ping(), with: key)
        let corrupted = RemoteEnvelope(
            v: signed.v, id: signed.id, ts: signed.ts,
            type: signed.type, payload: signed.payload,
            sig: "!!!not-valid-base64!!!"
        )
        XCTAssertFalse(EnvelopeSigner.verify(corrupted, with: key.publicKey))
    }

    /// CryptoKit `signature(for:)` ek randomness kullanır — iki çağrı farklı sig üretebilir,
    /// her ikisi de geçerlidir. Bu davranış API kontratı (Apple docs).
    func testRepeatedSignaturesAreBothValid() throws {
        let envelope = RemoteEnvelope(
            v: 2, id: "fixed-id", ts: 1_700_000_000,
            type: .userMessage,
            payload: EnvelopePayload(text: "deterministic", role: "user")
        )
        let a = try EnvelopeSigner.sign(envelope, with: key)
        let b = try EnvelopeSigner.sign(envelope, with: key)
        XCTAssertTrue(EnvelopeSigner.verify(a, with: key.publicKey))
        XCTAssertTrue(EnvelopeSigner.verify(b, with: key.publicKey))
    }

    func testCanonicalBytesIgnoresExistingSig() throws {
        let envelope = RemoteEnvelope(
            v: 2, id: "x", ts: 0, type: .ping, payload: nil, sig: nil
        )
        let withSig = RemoteEnvelope(
            v: 2, id: "x", ts: 0, type: .ping, payload: nil, sig: "stale-sig"
        )
        let bytesA = try EnvelopeSigner.canonicalBytes(of: envelope)
        let bytesB = try EnvelopeSigner.canonicalBytes(of: withSig)
        XCTAssertEqual(bytesA, bytesB)
    }

    func testReSigningProducesValidSignature() throws {
        let envelope = RemoteEnvelope.ping()
        let first = try EnvelopeSigner.sign(envelope, with: key)
        let second = try EnvelopeSigner.sign(first, with: key)
        XCTAssertNotEqual(second.sig, "stale-sig")
        XCTAssertTrue(EnvelopeSigner.verify(second, with: key.publicKey))
        // first imzası ikinci envelope'a uymaz (yeni randomness)
        XCTAssertTrue(EnvelopeSigner.verify(first, with: key.publicKey))
    }
}
