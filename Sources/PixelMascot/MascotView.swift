import SwiftUI

public struct MascotView: View {
    public let state: MascotState
    public let palette: MascotPalette
    public let size: CGFloat

    /// **Sprint 5 (mascot polish):** State `.error`'a geçtiği anki referans
    /// zamanı — shake elapsed hesabında kullanılır. nil = henüz error'a
    /// geçmedi veya 0.5s'lik shake bitti.
    @State private var errorEnteredAt: Date? = nil

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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let offset = currentOffset(time: time, now: context.date)
            let frameIndex = currentFrameIndex(time: time)
            let frame = PixelMascot.frame(for: state, atFrameIndex: frameIndex)

            Canvas { ctx, canvasSize in
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
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: size, height: size)
            .offset(offset)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: state)
        .onChange(of: state) { _, newState in
            if newState == .error {
                errorEnteredAt = Date()
            } else {
                errorEnteredAt = nil
            }
        }
    }

    /// State'e göre offset (idle bob / thinking wobble / error shake).
    private func currentOffset(time: Double, now: Date) -> CGSize {
        switch state {
        case .idle:
            return MascotAnimationClock.idleOffset(time: time)
        case .thinking:
            return MascotAnimationClock.thinkingOffset(time: time)
        case .speaking:
            return .zero
        case .error:
            guard let entered = errorEnteredAt else { return .zero }
            let elapsed = now.timeIntervalSince(entered)
            return MascotAnimationClock.errorShakeOffset(elapsed: elapsed)
        }
    }

    /// Speaking state çoklu frame; diğerleri 0 sabit.
    private func currentFrameIndex(time: Double) -> Int {
        switch state {
        case .speaking: return MascotAnimationClock.speakingFrameIndex(time: time)
        default: return 0
        }
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
