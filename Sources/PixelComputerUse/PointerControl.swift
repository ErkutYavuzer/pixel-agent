import Foundation
import PixelCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(AppKit)
import AppKit
#endif

/// **Faz 3b (ADR-0029):** Mouse tıklamasına eşlik edebilecek modifier tuşlar.
///
/// `OptionSet` — birden fazla flag kombinlenebilir: `[.command, .shift]`.
/// CGEvent'in `CGEventFlags` bayrağına çevrilir.
public struct ModifierFlags: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let command = ModifierFlags(rawValue: 1 << 0)
    public static let option  = ModifierFlags(rawValue: 1 << 1)
    public static let shift   = ModifierFlags(rawValue: 1 << 2)
    public static let control = ModifierFlags(rawValue: 1 << 3)

    /// Caller's free-form string array → ModifierFlags. Bilinmeyen anahtarlar
    /// silently atlanır.
    public static func parse(_ names: [String]) -> ModifierFlags {
        var flags: ModifierFlags = []
        for name in names {
            switch name.lowercased() {
            case "command", "cmd", "⌘": flags.insert(.command)
            case "option", "opt", "alt", "⌥": flags.insert(.option)
            case "shift", "⇧": flags.insert(.shift)
            case "control", "ctrl", "⌃": flags.insert(.control)
            default: break
            }
        }
        return flags
    }

    #if canImport(CoreGraphics)
    /// CGEvent'in setFlags'e geçecek raw CGEventFlags.
    var cgEventFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.command) { f.insert(.maskCommand) }
        if contains(.option)  { f.insert(.maskAlternate) }
        if contains(.shift)   { f.insert(.maskShift) }
        if contains(.control) { f.insert(.maskControl) }
        return f
    }
    #endif
}

/// CGEvent ile mouse/keyboard inject. Tüm metodlar MainActor'da çalışır.
///
/// `ToolArbiter.shared.with([.pointer])` ile sarılır — paralel subagent veya
/// dual-agent peer'lar aynı anda fareyi/klavyeyi tutamaz (ADR-0005, ADR-0026).
@MainActor
enum PointerControl {

    // MARK: - Mouse

    /// `point`'e `count` kez sol-tıklama. count=2 double-click.
    /// `modifiers` set ise tüm tıklamalar bu flag'lerle gönderilir (örn.
    /// `.command` = ⌘-click).
    ///
    /// Tüm tıklama serisi tek arbiter acquire altında — paralel subagent
    /// double-click ortasında araya giremez. CGEvent.post MainActor gerektirir
    /// (background thread'den çağırmak undefined behavior), bu yüzden arbiter
    /// body içinden MainActor.run hop edilir.
    static func click(at point: CGPoint, count: Int = 1, modifiers: ModifierFlags = []) async throws {
        #if canImport(CoreGraphics)
        guard count >= 1 else { return }
        try await ToolArbiter.shared.with([.pointer]) {
            try await MainActor.run {
                for i in 0..<count {
                    try postMouseDown(at: point, clickCount: i + 1, modifiers: modifiers)
                    try postMouseUp(at: point, clickCount: i + 1, modifiers: modifiers)
                }
            }
        }
        #else
        throw ComputerUseError.unsupported(reason: "CoreGraphics yok")
        #endif
    }

    #if canImport(CoreGraphics)
    private static func postMouseDown(at point: CGPoint, clickCount: Int, modifiers: ModifierFlags) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ComputerUseError.eventInjectionFailed(reason: "CGEvent leftMouseDown")
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        if !modifiers.isEmpty { event.flags = modifiers.cgEventFlags }
        event.post(tap: .cghidEventTap)
    }

    private static func postMouseUp(at point: CGPoint, clickCount: Int, modifiers: ModifierFlags) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ComputerUseError.eventInjectionFailed(reason: "CGEvent leftMouseUp")
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        if !modifiers.isEmpty { event.flags = modifiers.cgEventFlags }
        event.post(tap: .cghidEventTap)
    }
    #endif

    // MARK: - Keyboard

    /// Metni grapheme cluster sırasıyla gönderir (IME-aware). Tüm metin tek
    /// arbiter acquire altında — yarı yazılmış string'e başka inject araya giremez.
    ///
    /// **Faz 3b (ADR-0029):** Önceki versiyonda per-`Unicode.Scalar` iterasyon
    /// yapılıyordu; "👋🏼" gibi multi-scalar grapheme'ler iki ayrı keypress'e
    /// bölünüyordu. Şimdi per-`Character` (grapheme cluster) — her grapheme
    /// tek keyDown + keyUp olarak gider.
    static func typeText(_ text: String) async throws {
        #if canImport(CoreGraphics)
        try await ToolArbiter.shared.with([.pointer]) {
            try await MainActor.run {
                for chunk in unicodeChunks(for: text) {
                    try postUnicodeChunk(chunk)
                }
            }
        }
        #else
        throw ComputerUseError.unsupported(reason: "CoreGraphics yok")
        #endif
    }

    /// **Faz 3b:** `text`'i grapheme cluster sınırlarında parçalayıp her birinin
    /// UTF-16 code unit dizisini döndürür. Saf fonksiyon — AX/CGEvent bağımsız,
    /// unit-test friendly. Türkçe, emoji (ZWJ + skin-tone), diakritik tek pair.
    ///
    /// `nonisolated` — enum'un @MainActor izolasyonundan bağımsız; testlerden
    /// senkron çağrılabilir.
    nonisolated static func unicodeChunks(for text: String) -> [[UInt16]] {
        text.map { Array(String($0).utf16) }
    }

    #if canImport(CoreGraphics)
    private static func postUnicodeChunk(_ utf16: [UInt16]) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw ComputerUseError.eventInjectionFailed(reason: "CGEvent keyboardEvent")
        }
        utf16.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
            }
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    #endif
}
