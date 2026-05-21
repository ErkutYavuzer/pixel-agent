import XCTest
import CryptoKit
@testable import PixelRemote

final class KeyStoreTests: XCTestCase {
    private let service = "test.pixel-agent.keystore"
    private let account = "remote-signing-key"

    func testLoadOrCreateReturnsSameKeyOnSecondCall() throws {
        let store = InMemoryKeyStore()
        let first = try store.loadOrCreate(service: service, account: account)
        let second = try store.loadOrCreate(service: service, account: account)
        XCTAssertEqual(first.rawRepresentation, second.rawRepresentation)
    }

    func testDifferentAccountsProduceDifferentKeys() throws {
        let store = InMemoryKeyStore()
        let a = try store.loadOrCreate(service: service, account: "account-a")
        let b = try store.loadOrCreate(service: service, account: "account-b")
        XCTAssertNotEqual(a.rawRepresentation, b.rawRepresentation)
    }

    func testDifferentServicesProduceDifferentKeys() throws {
        let store = InMemoryKeyStore()
        let a = try store.loadOrCreate(service: "service-a", account: account)
        let b = try store.loadOrCreate(service: "service-b", account: account)
        XCTAssertNotEqual(a.rawRepresentation, b.rawRepresentation)
    }

    func testClearForcesNewKeyOnNextLoad() throws {
        let store = InMemoryKeyStore()
        let first = try store.loadOrCreate(service: service, account: account)
        try store.clear(service: service, account: account)
        let second = try store.loadOrCreate(service: service, account: account)
        XCTAssertNotEqual(first.rawRepresentation, second.rawRepresentation)
    }

    func testClearMissingKeyDoesNotThrow() {
        let store = InMemoryKeyStore()
        XCTAssertNoThrow(try store.clear(service: service, account: "never-created"))
    }

    func testKeyCanSignAndVerifyAcrossLoads() throws {
        let store = InMemoryKeyStore()
        let envelope = RemoteEnvelope.userMessage(text: "persist")

        let key1 = try store.loadOrCreate(service: service, account: account)
        let signed = try EnvelopeSigner.sign(envelope, with: key1)

        // Aynı store'dan tekrar yüklenen key, üretilen imzayı doğrulayabilmeli.
        let key2 = try store.loadOrCreate(service: service, account: account)
        XCTAssertTrue(EnvelopeSigner.verify(signed, with: key2.publicKey))
    }
}
