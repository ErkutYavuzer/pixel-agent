import XCTest

@testable import PixelTools

final class SoundEffectTests: XCTestCase {
    func testSystemSoundNameConstants() {
        XCTAssertEqual(SoundEffect.messageReceived, "Glass")
        XCTAssertEqual(SoundEffect.errorOccurred, "Basso")
        XCTAssertEqual(SoundEffect.neutralBeep, "Tink")
    }
}
