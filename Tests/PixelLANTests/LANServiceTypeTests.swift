import XCTest
@testable import PixelLAN

final class LANServiceTypeTests: XCTestCase {
    func testServiceTypeMatchesRFC6335ShortName() {
        // RFC 6335: ≤15 char, ASCII, _ ile başlamalı, lowercase letters/digits/hyphen
        let name = LANServiceType.bonjour
        XCTAssertTrue(name.hasPrefix("_"))
        XCTAssertTrue(name.hasSuffix("._tcp"))
        // ServiceType prefix ("_pixel-agent") 15 chars sınırına uyar
        let nameOnly = name.replacingOccurrences(of: "._tcp", with: "")
            .replacingOccurrences(of: "_", with: "")
        XCTAssertLessThanOrEqual(nameOnly.count, 15)
        XCTAssertEqual(nameOnly, nameOnly.lowercased())
    }

    func testDomainIsLocal() {
        XCTAssertEqual(LANServiceType.domain, "local.")
    }

    func testTXTKeysAreShort() {
        // mDNS TXT key'ler kısa olmalı; bizim convention: 2 char veya less
        XCTAssertEqual(LANServiceType.TXTKey.publicKey, "pk")
        XCTAssertEqual(LANServiceType.TXTKey.protocolVersion, "v")
    }

    func testDefaultPortIsAuto() {
        XCTAssertEqual(LANServiceType.defaultPort, 0)
    }
}
