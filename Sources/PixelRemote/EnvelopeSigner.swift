import Foundation
import CryptoKit

/// ed25519 ile RemoteEnvelope imza/doğrulama.
///
/// İmzalama akışı: envelope'un `sig` alanı çıkarılır → canonical JSON encode (sortedKeys)
/// → ed25519 ile imzala → base64. Doğrulama tam tersine işler.
///
/// ed25519 deterministik olduğu için aynı (key, envelope) ikilisi her zaman aynı
/// imzayı üretir. Bu özellik testleri sadeleştirir.
public enum EnvelopeSigner {
    /// Envelope'ı verilen private key ile imzalar; yeni `sig` set edilmiş bir
    /// envelope döner. Mevcut `sig` alanı yoksayılır (yeniden imzalamayı destekler).
    public static func sign(
        _ envelope: RemoteEnvelope,
        with privateKey: Curve25519.Signing.PrivateKey
    ) throws -> RemoteEnvelope {
        let bytes = try canonicalBytes(of: envelope)
        let signature = try privateKey.signature(for: bytes)
        let sigB64 = signature.base64EncodedString()
        return RemoteEnvelope(
            v: envelope.v,
            id: envelope.id,
            ts: envelope.ts,
            type: envelope.type,
            payload: envelope.payload,
            sig: sigB64
        )
    }

    /// Envelope imzasının verilen public key ile geçerli olup olmadığını döner.
    /// `sig` yoksa veya bozuksa false.
    public static func verify(
        _ envelope: RemoteEnvelope,
        with publicKey: Curve25519.Signing.PublicKey
    ) -> Bool {
        guard let sigB64 = envelope.sig,
              let signature = Data(base64Encoded: sigB64),
              let bytes = try? canonicalBytes(of: envelope)
        else { return false }
        return publicKey.isValidSignature(signature, for: bytes)
    }

    /// `sig` alanı boşaltılarak canonical (sortedKeys) JSON byte temsili.
    /// Hem imza üretirken hem de doğrularken aynı dönüşüm uygulanır.
    static func canonicalBytes(of envelope: RemoteEnvelope) throws -> Data {
        let unsigned = RemoteEnvelope(
            v: envelope.v,
            id: envelope.id,
            ts: envelope.ts,
            type: envelope.type,
            payload: envelope.payload,
            sig: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(unsigned)
    }
}
