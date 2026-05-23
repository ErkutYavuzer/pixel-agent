import PixelCore
import SwiftUI

/// Asistan ilk token'ı henüz dökmeden gösterilen 3 nokta pulse animasyonu (A2).
///
/// 3 küçük daire 0.18s gecikmeyle peş peşe scale + opacity yaparak "yazıyor…"
/// hissi verir. `repeatForever` ile sürekli; `onAppear`'da delay'li tetiklenir.
/// View kaybolduğunda SwiftUI animasyon state'ini bırakır.
struct TypingIndicatorView: View {
    private static let dotCount = 3
    private static let dotSize: CGFloat = 7
    private static let spacing: CGFloat = 5
    private static let interDelay: Double = 0.18
    private static let cycleDuration: Double = 0.55

    @State private var scales: [CGFloat] = Array(repeating: 0.5, count: dotCount)

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<Self.dotCount, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .scaleEffect(scales[i])
                    .opacity(0.4 + 0.6 * Double(scales[i]))
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            for i in 0..<Self.dotCount {
                withAnimation(
                    .easeInOut(duration: Self.cycleDuration)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * Self.interDelay)
                ) {
                    scales[i] = 1.0
                }
            }
        }
        .accessibilityLabel("Pixel yazıyor")
    }
}

// MARK: - Pure helper (testable)

/// Verilen mesajın "şu anda streaming edilen son assistant mesajı" olup
/// olmadığını döner. View tarafında TypingIndicatorView'ı ne zaman göstereceğimize
/// karar vermek için kullanılır.
///
/// Saf: SwiftUI'a bağımlı değil, hermetik test edilebilir.
enum StreamingMessageHelper {
    static func isStreamingTail(
        message: Message,
        in messages: [Message],
        isStreaming: Bool
    ) -> Bool {
        guard isStreaming else { return false }
        guard message.role == .assistant else { return false }
        return message.id == messages.last?.id
    }
}
