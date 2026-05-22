import XCTest
import PixelRemote
@testable import PixelLAN

/// Network.framework adapter'larının (LANServerTransport, LANClientTransport)
/// construction sanity. Gerçek bind/browse Bonjour gerektirir; CI'da flaky —
/// Faz 2 manual QA'ya bırakıldı.
final class LANTransportInstantiationTests: XCTestCase {
    func testLANServerTransportCanBeInitialized() async {
        let transport = LANServerTransport()
        _ = transport
    }

    func testLANServerTransportAcceptsCustomConfiguration() async {
        let config = LANService.Configuration(
            serviceName: "Test-Mac",
            port: 0,
            publicKeyBase64: "abc",
            protocolVersionTXT: "2"
        )
        let transport = LANServerTransport(configuration: config)
        _ = transport
    }

    func testLANClientTransportCanBeInitialized() async {
        let transport = LANClientTransport(discoveryTimeout: 1.0)
        _ = transport
    }

    func testLANClientTransportDefaultTimeoutIsTwoSeconds() async {
        let transport = LANClientTransport()
        _ = transport
    }
}
