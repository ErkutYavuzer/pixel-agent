import SwiftUI

public struct MascotView: View {
    public let state: MascotState
    public let palette: MascotPalette
    public let size: CGFloat

    public init(
        state: MascotState,
        palette: MascotPalette = .default,
        size: CGFloat = 48
    ) {
        self.state = state
        self.palette = palette
        self.size = size
    }

    public var body: some View {
        let frame = PixelMascot.frame(for: state)
        Canvas { context, canvasSize in
            let cellWidth = canvasSize.width / CGFloat(frame.width)
            let cellHeight = canvasSize.height / CGFloat(frame.height)
            for y in 0..<frame.height {
                for x in 0..<frame.width {
                    let char = frame.cell(x: x, y: y)
                    guard let color = color(for: char) else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * cellWidth,
                        y: CGFloat(y) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    private func color(for char: Character) -> Color? {
        switch char {
        case "X": return palette.body
        case "H": return palette.bodyHighlight
        case "S": return palette.bodyShadow
        case "O": return palette.eye
        case "o": return palette.bodyShadow
        case "x": return palette.eye
        case "M", "_": return palette.mouth
        default: return nil
        }
    }
}

#Preview("All states") {
    HStack(spacing: 16) {
        ForEach(MascotState.allCases, id: \.self) { state in
            VStack {
                MascotView(state: state, size: 64)
                Text(state.rawValue).font(.caption)
            }
        }
    }
    .padding()
}
