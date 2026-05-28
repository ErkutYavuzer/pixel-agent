import SwiftUI

public enum MascotState: String, CaseIterable, Sendable {
    case idle
    case thinking
    case speaking
    case error
    /// **Sprint 50 (v0.2.79):** Sesli modda mikrofon açık ve kullanıcı
    /// konuşurken — dikkatli "dinliyorum" hali. VoiceSession sürer (Mac-only).
    case listening
}

public struct MascotPalette: Sendable {
    public let body: Color
    public let bodyHighlight: Color
    public let bodyShadow: Color
    public let eye: Color
    public let mouth: Color

    public init(
        body: Color,
        bodyHighlight: Color,
        bodyShadow: Color,
        eye: Color,
        mouth: Color
    ) {
        self.body = body
        self.bodyHighlight = bodyHighlight
        self.bodyShadow = bodyShadow
        self.eye = eye
        self.mouth = mouth
    }

    public static let `default` = MascotPalette(
        body: Color(red: 0.45, green: 0.30, blue: 0.85),
        bodyHighlight: Color(red: 0.60, green: 0.45, blue: 0.95),
        bodyShadow: Color(red: 0.30, green: 0.18, blue: 0.65),
        eye: .white,
        mouth: .black
    )
}

public struct MascotFrame: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rows: [String]

    public init(ascii: String, width: Int = 12, height: Int = 12) {
        self.width = width
        self.height = height
        let lines = ascii.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var padded: [String] = []
        for y in 0..<height {
            let line = y < lines.count ? lines[y] : ""
            var row = line
            while row.count < width { row.append(".") }
            row = String(row.prefix(width))
            padded.append(row)
        }
        self.rows = padded
    }

    public func cell(x: Int, y: Int) -> Character {
        guard y >= 0, y < height, x >= 0, x < width else { return "." }
        let row = rows[y]
        return row[row.index(row.startIndex, offsetBy: x)]
    }
}

public enum PixelMascot {
    public static let version = "0.1.0"

    /// Verilen state için varsayılan (frame index 0) frame'i döner. Eski API
    /// — geriye uyumlu kalır.
    public static func frame(for state: MascotState) -> MascotFrame {
        frame(for: state, atFrameIndex: 0)
    }

    /// **Sprint 5 (mascot polish):** State'in çoklu frame'i varsa index'e
    /// göre döndürür. Şu an yalnızca `.speaking` 2 frame (0 = open mouth,
    /// 1 = closed mouth); diğer state'ler tek frame (her index aynı sonucu
    /// döner — out-of-bounds yumuşak fallback).
    public static func frame(for state: MascotState, atFrameIndex index: Int) -> MascotFrame {
        switch state {
        case .idle: return idleFrame
        case .thinking: return thinkingFrame
        case .speaking:
            return index % 2 == 0 ? speakingFrame : speakingFrameClosed
        case .error: return errorFrame
        case .listening: return listeningFrame
        }
    }

    public static let idleFrame = MascotFrame(ascii: """
    ............
    ....XXXX....
    ...HXXXXS...
    ..HXXXXXXS..
    ..XOXXXXOX..
    ..XOXXXXOX..
    ..XXX__XXX..
    ..XSXXXXSX..
    ...SXXXXS...
    ....SXXS....
    ............
    ............
    """)

    public static let thinkingFrame = MascotFrame(ascii: """
    ............
    ....XXXX....
    ...HXXXXS...
    ..HXXXXXXS..
    ..XoXXXXoX..
    ..XoXXXXoX..
    ..XXXXXXXX..
    ..XSXXXXSX..
    ...SXXXXS...
    ....SXXS....
    ............
    ............
    """)

    public static let speakingFrame = MascotFrame(ascii: """
    ............
    ....XXXX....
    ...HXXXXS...
    ..HXXXXXXS..
    ..XOXXXXOX..
    ..XOXXXXOX..
    ..XXMMMMXX..
    ..XSMMMMSX..
    ...SXXXXS...
    ....SXXS....
    ............
    ............
    """)

    /// **Sprint 5 (mascot polish):** Ağız "kapalı/küçülmüş" 2. konuşma frame'i.
    /// `MascotAnimationClock.speakingFrameIndex(time:)` 5Hz'de 0↔1 arasında
    /// alternates → ağız açılıp kapanır görüntüsü.
    public static let speakingFrameClosed = MascotFrame(ascii: """
    ............
    ....XXXX....
    ...HXXXXS...
    ..HXXXXXXS..
    ..XOXXXXOX..
    ..XOXXXXOX..
    ..XXX__XXX..
    ..XSXXXXSX..
    ...SXXXXS...
    ....SXXS....
    ............
    ............
    """)

    public static let errorFrame = MascotFrame(ascii: """
    ............
    ....XXXX....
    ...HXXXXS...
    ..HXXXXXXS..
    ..XxXXXXxX..
    ..XxXXXXxX..
    ..XXX__XXX..
    ..XSXXXXSX..
    ...SXXXXS...
    ....SXXS....
    ............
    ............
    """)

    /// **Sprint 50 (v0.2.79):** Dinleme hali — gözler 2 hücre genişliğinde
    /// (idle'da tek hücre), "dikkatle dinliyorum" görüntüsü. Ağız idle gibi
    /// kapalı/nötr (`_`). Hareket `MascotAnimationClock.listeningOffset` ile
    /// idle'dan daha tetik yumuşak baş sallama.
    public static let listeningFrame = MascotFrame(ascii: """
    ............
    ....XXXX....
    ...HXXXXS...
    ..HXXXXXXS..
    ..XOOXXOOX..
    ..XOOXXOOX..
    ..XXX__XXX..
    ..XSXXXXSX..
    ...SXXXXS...
    ....SXXS....
    ............
    ............
    """)
}
