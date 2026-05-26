import XCTest
@testable import PixelVoice

/// **Sprint 42 (v0.2.69):** VoiceCredentialsStore CRUD tests.
final class VoiceCredentialsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: VoiceCredentialsStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.voice.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = VoiceCredentialsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEmptyStoreReturnsNil() async {
        let openai = await store.openaiKey()
        let gemini = await store.geminiKey()
        XCTAssertNil(openai)
        XCTAssertNil(gemini)
    }

    func testSetAndReadOpenAIKey() async {
        await store.setOpenAIKey("sk-test-123")
        let key = await store.openaiKey()
        XCTAssertEqual(key, "sk-test-123")
    }

    func testSetAndReadGeminiKey() async {
        await store.setGeminiKey("AIza-test-456")
        let key = await store.geminiKey()
        XCTAssertEqual(key, "AIza-test-456")
    }

    func testSetNilRemovesKey() async {
        await store.setOpenAIKey("sk-test")
        await store.setOpenAIKey(nil)
        let key = await store.openaiKey()
        XCTAssertNil(key)
    }

    func testSetEmptyStringRemovesKey() async {
        await store.setOpenAIKey("sk-test")
        await store.setOpenAIKey("   ")
        let key = await store.openaiKey()
        XCTAssertNil(key, "Whitespace-only string treated as nil")
    }

    func testHasKeyApple() async {
        let has = await store.hasKey(for: .apple)
        XCTAssertTrue(has, "Apple never needs key")
    }

    func testHasKeyOpenAIBeforeSet() async {
        let has = await store.hasKey(for: .openaiRealtime)
        XCTAssertFalse(has)
    }

    func testHasKeyOpenAIAfterSet() async {
        await store.setOpenAIKey("sk-test")
        let has = await store.hasKey(for: .openaiRealtime)
        XCTAssertTrue(has)
    }

    // MARK: - VoiceProviderKind

    func testProviderKindDisplayNames() {
        XCTAssertFalse(VoiceProviderKind.apple.displayName.isEmpty)
        XCTAssertTrue(VoiceProviderKind.openaiRealtime.displayName.contains("OpenAI"))
        XCTAssertTrue(VoiceProviderKind.geminiLive.displayName.contains("Gemini"))
    }

    func testProviderKindDescriptions() {
        for kind in VoiceProviderKind.allCases {
            XCTAssertFalse(kind.description.isEmpty, "\(kind) description boş")
        }
    }

    func testAppleIsAvailable() {
        XCTAssertTrue(VoiceProviderKind.apple.isAvailable)
    }

    func testRealtimeProvidersAvailability() {
        // Sprint 43 (v0.2.70): OpenAI Realtime aktif.
        // Sprint 44'te Gemini Live aktive olacak.
        XCTAssertTrue(VoiceProviderKind.openaiRealtime.isAvailable)
        XCTAssertFalse(VoiceProviderKind.geminiLive.isAvailable)
    }

    func testAllCasesCount() {
        XCTAssertEqual(VoiceProviderKind.allCases.count, 3)
    }
}
