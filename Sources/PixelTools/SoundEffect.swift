import AppKit

public enum SoundEffect {
    public static let messageReceived: String = "Glass"
    public static let errorOccurred: String = "Basso"
    public static let neutralBeep: String = "Tink"

    @MainActor
    public static func play(_ systemSoundName: String) {
        guard let sound = NSSound(named: NSSound.Name(systemSoundName)) else { return }
        sound.play()
    }
}
