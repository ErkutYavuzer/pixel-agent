import Foundation
import PixelCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(AppKit)
import AppKit
#endif

/// CGEvent ile mouse/keyboard inject. Tüm metodlar MainActor'da çalışır.
///
/// `ToolArbiter.shared.with([.pointer])` ile sarılır — paralel subagent veya
/// dual-agent peer'lar aynı anda fareyi/klavyeyi tutamaz (ADR-0005, ADR-0026).
@MainActor
enum PointerControl {

    // MARK: - Mouse

    /// `point`'e `count` kez sol-tıklama. count=2 double-click.
    /// Tüm tıklama serisi tek arbiter acquire altında — paralel subagent
    /// double-click ortasında araya giremez. CGEvent.post MainActor gerektirir
    /// (background thread'den çağırmak undefined behavior), bu yüzden arbiter
    /// body içinden MainActor.run hop edilir.
    static func click(at point: CGPoint, count: Int = 1) async throws {
        #if canImport(CoreGraphics)
        guard count >= 1 else { return }
        try await ToolArbiter.shared.with([.pointer]) {
            try await MainActor.run {
                for i in 0..<count {
                    try postMouseDown(at: point, clickCount: i + 1)
                    try postMouseUp(at: point, clickCount: i + 1)
                }
            }
        }
        #else
        throw ComputerUseError.unsupported(reason: "CoreGraphics yok")
        #endif
    }

    #if canImport(CoreGraphics)
    private static func postMouseDown(at point: CGPoint, clickCount: Int) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ComputerUseError.eventInjectionFailed(reason: "CGEvent leftMouseDown")
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
    }

    private static func postMouseUp(at point: CGPoint, clickCount: Int) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ComputerUseError.eventInjectionFailed(reason: "CGEvent leftMouseUp")
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
    }
    #endif

    // MARK: - Keyboard

    /// Metni tek-tek karakter olarak gönderir. Tüm metin tek arbiter acquire
    /// altında — yarı yazılmış string'e başka inject araya giremez.
    static func typeText(_ text: String) async throws {
        #if canImport(CoreGraphics)
        try await ToolArbiter.shared.with([.pointer]) {
            try await MainActor.run {
                for scalar in text.unicodeScalars {
                    try postUnicodeKey(scalar)
                }
            }
        }
        #else
        throw ComputerUseError.unsupported(reason: "CoreGraphics yok")
        #endif
    }

    #if canImport(CoreGraphics)
    private static func postUnicodeKey(_ scalar: Unicode.Scalar) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw ComputerUseError.eventInjectionFailed(reason: "CGEvent keyboardEvent")
        }
        let utf16 = Array(String(scalar).utf16)
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
