import XCTest
@testable import PixelLAN

/// Gerçek Bonjour broadcast'i CI'da flaky olur (network izolasyonu, multicast
/// kısıtları). Bu testler sadece instantiation + temel API surface'i doğrular.
/// End-to-end manual QA / Faz 2'de wire-up testleriyle yapılır.
final class LANInstantiationTests: XCTestCase {
    func testLANServiceCanBeCreated() async {
        let service = LANService()
        let port = await service.listenerPort
        XCTAssertNil(port, "start çağrılmadan port yok")
    }

    func testLANServiceConfigurationDefaults() {
        let config = LANService.Configuration()
        XCTAssertNil(config.serviceName)
        XCTAssertEqual(config.port, 0)
        XCTAssertNil(config.publicKeyBase64)
    }

    func testLANServiceConfigurationCustom() {
        let config = LANService.Configuration(
            serviceName: "Erkut'un Mac'i",
            port: 17655,
            publicKeyBase64: "AAAA-base64-pubkey",
            protocolVersionTXT: "2"
        )
        XCTAssertEqual(config.serviceName, "Erkut'un Mac'i")
        XCTAssertEqual(config.port, 17655)
        XCTAssertEqual(config.publicKeyBase64, "AAAA-base64-pubkey")
        XCTAssertEqual(config.protocolVersionTXT, "2")
    }

    func testLANClientCanBeCreated() async {
        let client = LANClient()
        _ = client
    }
}
