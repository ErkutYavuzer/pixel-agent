import PixelCore

public enum PixelRemote {
    public static let version = "0.2.0"
    /// Protocol v2: signed envelopes (ed25519). v1 (v0.1.x) unsigned, geriye uyum yok.
    public static let protocolVersion = 2
}
