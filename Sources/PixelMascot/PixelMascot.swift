import SwiftUI

public enum MascotState: String, CaseIterable, Sendable {
    case idle
    case thinking
    case speaking
    case error
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

    public static func frame(for state: MascotState) -> MascotFrame {
        switch state {
        case .idle: return idleFrame
        case .thinking: return thinkingFrame
        case .speaking: return speakingFrame
        case .error: return errorFrame
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
}
