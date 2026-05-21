import Foundation
import CryptoKit
import Security

/// Cihaz başına kalıcı ed25519 imzalama anahtarı depolama soyutlaması.
///
/// Üretim: `KeychainKeyStore` (macOS+iOS, Security framework).
/// Test: `InMemoryKeyStore` (hermetic; CI'da Keychain'e dokunmaz).
public protocol KeyStoring: Sendable {
    /// İlgili (service, account) için kayıtlı private key varsa onu, yoksa yeni
    /// üretip kaydederek dönen tek atom işlem.
    func loadOrCreate(service: String, account: String) throws -> Curve25519.Signing.PrivateKey

    /// Anahtarı siler. Yoksa hata atmaz.
    func clear(service: String, account: String) throws
}

public enum KeyStoreError: Error, LocalizedError, Equatable {
    case keychainStatus(OSStatus, operation: String)
    case invalidKeyData

    public var errorDescription: String? {
        switch self {
        case .keychainStatus(let status, let op):
            return "Keychain \(op) hatası: status=\(status)"
        case .invalidKeyData:
            return "Geçersiz anahtar verisi (raw representation 32 byte olmalı)."
        }
    }
}

/// `Security.framework` (kSecClassGenericPassword) kullanır.
/// Raw 32-byte private key'i `kSecValueData` olarak saklar.
public struct KeychainKeyStore: KeyStoring {
    public init() {}

    public func loadOrCreate(service: String, account: String) throws -> Curve25519.Signing.PrivateKey {
        if let data = try Self.loadData(service: service, account: account) {
            do {
                return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
            } catch {
                // Bozuk veriyle karşılaşırsak (eski format vs.) temizle ve yeni üret.
                try? clear(service: service, account: account)
            }
        }
        let key = Curve25519.Signing.PrivateKey()
        try Self.store(data: key.rawRepresentation, service: service, account: account)
        return key
    }

    public func clear(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychainStatus(status, operation: "delete")
        }
    }

    // MARK: - Internal

    private static func loadData(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychainStatus(status, operation: "load")
        }
    }

    private static func store(data: Data, service: String, account: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyStoreError.keychainStatus(status, operation: "add")
        }
    }
}

/// Process-içi memory-resident KeyStore — sadece test/debug için.
///
/// Sandbox dışındaki Swift unit test'leri Keychain erişimi alamayabilir;
/// CI'da hermetic tutmak için bu impl. kullanılır.
public final class InMemoryKeyStore: KeyStoring, @unchecked Sendable {
    private struct Key: Hashable { let service: String; let account: String }
    private var store: [Key: Curve25519.Signing.PrivateKey] = [:]
    private let lock = NSLock()

    public init() {}

    public func loadOrCreate(service: String, account: String) throws -> Curve25519.Signing.PrivateKey {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(service: service, account: account)
        if let existing = store[key] {
            return existing
        }
        let new = Curve25519.Signing.PrivateKey()
        store[key] = new
        return new
    }

    public func clear(service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: Key(service: service, account: account))
    }
}
