import XCTest
@testable import PixelMacApp

/// **Sprint 47 (v0.2.75):** RelayURLResolver fallback chain priority tests.
final class RelayURLResolverTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.relay.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Priority chain

    func testCustomURLHighestPriority() {
        defaults.set("wss://custom.example.com", forKey: RelayURLResolver.customURLDefaultsKey)
        let url = RelayURLResolver.resolve(
            defaults: defaults,
            environment: ["PIXEL_RELAY_URL": "wss://env.example.com"]
        )
        XCTAssertEqual(url, "wss://custom.example.com", "Custom URL env'i bile geçer")
    }

    func testEnvironmentSecondPriority() {
        let url = RelayURLResolver.resolve(
            defaults: defaults,
            environment: ["PIXEL_RELAY_URL": "wss://env.example.com"]
        )
        XCTAssertEqual(url, "wss://env.example.com")
    }

    func testFallbackToLANOrLocalhost() {
        let url = RelayURLResolver.resolve(defaults: defaults, environment: [:])
        XCTAssertTrue(
            url.hasPrefix("ws://") || url.hasPrefix("wss://"),
            "LAN veya localhost fallback bir WS URL döndürmeli"
        )
        // En azından localhost
        XCTAssertTrue(url.contains("8787"), "Port 8787 her fallback'te")
    }

    // MARK: - Source classification

    func testSourceCustom() {
        defaults.set("wss://my-relay.workers.dev", forKey: RelayURLResolver.customURLDefaultsKey)
        let source = RelayURLResolver.resolveSource(defaults: defaults, environment: [:])
        if case .custom(let url) = source {
            XCTAssertEqual(url, "wss://my-relay.workers.dev")
        } else {
            XCTFail("Custom source bekleniyordu, oldu: \(source)")
        }
    }

    func testSourceEnvironment() {
        let source = RelayURLResolver.resolveSource(
            defaults: defaults,
            environment: ["PIXEL_RELAY_URL": "wss://env.example.com"]
        )
        if case .environment(let url) = source {
            XCTAssertEqual(url, "wss://env.example.com")
        } else {
            XCTFail("Environment source bekleniyordu, oldu: \(source)")
        }
    }

    func testSourceFallback() {
        let source = RelayURLResolver.resolveSource(defaults: defaults, environment: [:])
        switch source {
        case .lan, .localhost:
            break  // Beklenen
        default:
            XCTFail("LAN veya localhost fallback bekleniyordu, oldu: \(source)")
        }
    }

    func testSourceURLAccessor() {
        let source = RelayURLResolver.Source.custom("wss://test.example")
        XCTAssertEqual(source.url, "wss://test.example")
        let lanSource = RelayURLResolver.Source.lan(ip: "192.168.1.100")
        XCTAssertEqual(lanSource.url, "ws://192.168.1.100:8787")
        let localhost = RelayURLResolver.Source.localhost
        XCTAssertEqual(localhost.url, "ws://localhost:8787")
    }

    func testSourceDisplayNames() {
        XCTAssertEqual(RelayURLResolver.Source.custom("x").displayName, "Özel")
        XCTAssertEqual(RelayURLResolver.Source.environment("x").displayName, "PIXEL_RELAY_URL")
        XCTAssertEqual(RelayURLResolver.Source.production("x").displayName, "Cloudflare")
        XCTAssertEqual(RelayURLResolver.Source.lan(ip: "1.2.3.4").displayName, "LAN")
        XCTAssertEqual(RelayURLResolver.Source.localhost.displayName, "localhost")
    }

    // MARK: - setCustomURL

    func testSetCustomURLPersists() {
        RelayURLResolver.setCustomURL("wss://saved.example.com", defaults: defaults)
        let stored = defaults.string(forKey: RelayURLResolver.customURLDefaultsKey)
        XCTAssertEqual(stored, "wss://saved.example.com")
    }

    func testSetCustomURLNilClears() {
        defaults.set("wss://old.example.com", forKey: RelayURLResolver.customURLDefaultsKey)
        RelayURLResolver.setCustomURL(nil, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: RelayURLResolver.customURLDefaultsKey))
    }

    func testSetCustomURLWhitespaceClears() {
        defaults.set("wss://old.example.com", forKey: RelayURLResolver.customURLDefaultsKey)
        RelayURLResolver.setCustomURL("   ", defaults: defaults)
        XCTAssertNil(defaults.string(forKey: RelayURLResolver.customURLDefaultsKey))
    }

    func testEmptyStringDoesNotOverrideEnv() {
        defaults.set("", forKey: RelayURLResolver.customURLDefaultsKey)
        let url = RelayURLResolver.resolve(
            defaults: defaults,
            environment: ["PIXEL_RELAY_URL": "wss://env.example.com"]
        )
        XCTAssertEqual(url, "wss://env.example.com", "Empty custom URL env'e düşer")
    }

    // MARK: - LAN detection (best-effort — environment dependent)

    func testDetectLANIPv4ReturnsValidFormat() {
        // Test ortamında en0/en1 olmayabilir; nil veya geçerli IP olmalı.
        if let ip = RelayURLResolver.detectLANIPv4() {
            XCTAssertFalse(ip.isEmpty)
            XCTAssertNotEqual(ip, "127.0.0.1", "localhost dışı IP")
            XCTAssertTrue(ip.contains("."), "IPv4 dotted format")
        }
    }
}
