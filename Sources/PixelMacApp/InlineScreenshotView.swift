import AppKit
import PixelComputerUse
import SwiftUI

/// Chat akışında inline gösterilen ekran görüntüsü + opsiyonel SoM mark
/// overlay'leri (C2/C3). Görsel PixelComputerUse'un `ScreenshotResult.pngData`
/// + `marks` çıktısını tüketir.
///
/// Tasarım kararları:
/// - `NSImage(data:)` ile PNG'yi yükle; `Image(nsImage:)` ile resizable + aspect-fit
///   render et. Max width ~520pt (chat bubble'ın doğal genişliğine uyar).
/// - Mark overlay'leri `GeometryReader` içinde — fitted size'ı saf
///   `ScreenshotMarkLayout` ile hesaplayıp her mark için pixel→point rect
///   çıkar.
/// - Her mark: outline + numaralı badge sol üst köşede.
struct InlineScreenshotView: View {
    let attachment: ScreenshotAttachment

    private static let maxWidth: CGFloat = 520
    private static let palette: [Color] = [
        .red, .orange, .yellow, .green, .blue, .indigo, .purple, .pink,
    ]

    private var image: NSImage? {
        NSImage(data: attachment.pngData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                imageWithOverlays(image: image)
            } else {
                placeholder
            }
            footer
        }
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func imageWithOverlays(image: NSImage) -> some View {
        GeometryReader { proxy in
            let fitted = ScreenshotMarkLayout.fittedSize(
                imagePixelSize: attachment.pixelSize,
                containerSize: proxy.size
            )
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                ForEach(Array(attachment.marks.enumerated()), id: \.element.id) { idx, mark in
                    overlay(for: mark, paletteIdx: idx, fitted: fitted)
                }
            }
            // Üst-sol köşeye hizala — fitted resim container'dan dar olabilir.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        // Yükseklik aspect-ratio + maxWidth ile belirlenir; sabit değil.
        .aspectRatio(
            CGSize(width: attachment.pixelSize.width, height: attachment.pixelSize.height),
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func overlay(for mark: SoMMark, paletteIdx: Int, fitted: CGSize) -> some View {
        let viewRect = ScreenshotMarkLayout.viewRect(
            forImageRect: mark.frameInImage,
            imagePixelSize: attachment.pixelSize,
            viewSize: fitted
        )
        let color = Self.palette[paletteIdx % Self.palette.count]
        ZStack(alignment: .topLeading) {
            // Outline
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, lineWidth: 2)
                .frame(width: viewRect.width, height: viewRect.height)
            // Numbered badge sol-üst içinde
            Text(mark.id)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color, in: Capsule())
                .offset(x: 2, y: 2)
        }
        .offset(x: viewRect.minX, y: viewRect.minY)
        .allowsHitTesting(false)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.gray.opacity(0.15))
            .frame(height: 120)
            .overlay(
                Label("Görsel yüklenemedi", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera")
                .foregroundStyle(.secondary)
            Text("\(Int(attachment.pixelSize.width))×\(Int(attachment.pixelSize.height)) px")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if !attachment.marks.isEmpty {
                Text("· \(attachment.marks.count) işaret")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
