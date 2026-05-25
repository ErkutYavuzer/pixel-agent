import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(CoreText)
import CoreText
#endif

/// **Faz 4 (ADR-0031):** Set-of-Mark visual annotation renderer.
///
/// `annotate(image:elements:imageScreenOrigin:imageLogicalSize:pixelSize:)`
/// her element için image üzerine numaralı badge + outline çizer. CGImage
/// origin top-left, CGContext origin bottom-left — internal CTM flip ile uyumlu
/// pixel koordinatlar kullanılır. Text rendering NSGraphicsContext (flipped:true)
/// üzerinden — pixel-tam glyph yerleşimi.
///
/// Element image bounding box'ı dışındaysa atlanır (`MarkLayout.computeMarkRect`
/// nil dönerse). Image bounds içinde kalan kısmı outline ile çevrelenir.
enum SoMRenderer {

    /// **Faz 5 (v0.2.38):** Önceki hardcoded sabitler `SoMOptions`'a taşındı.
    /// Geri uyumluluk için `annotate(...)` default `SoMOptions.default` kullanır
    /// (eski caller'lar değişmedi).

    /// Annotation entry point. Image üzerine N element için marker overlay'i çizer.
    ///
    /// - `image`: SCScreenshotManager çıktısı.
    /// - `elements`: işaretlenecek `UIElement` listesi (caller'ın `ui_query` sonucu).
    /// - `imageScreenOrigin`: image'in temsil ettiği bölgenin top-left logical
    ///   screen origin'i (window.frame.origin + opsiyonel titlebarOffset).
    /// - `imageLogicalSize`: bölgenin logical points cinsinden boyutu.
    /// - `options`: **Faz 5 (v0.2.38):** Görselleştirme parametreleri — palette,
    ///   outline/badge boyutları, badge placement strategy. `.default` eski
    ///   hardcoded davranışla aynı.
    /// - Returns: `(annotated CGImage, [SoMMark] in 1-bazlı ID sırasıyla)`.
    ///   Off-screen element'ler atlanır → `marks.count` ≤ `elements.count`.
    static func annotate(
        image: CGImage,
        elements: [UIElement],
        imageScreenOrigin: CGPoint,
        imageLogicalSize: CGSize,
        options: SoMOptions = .default
    ) throws -> (CGImage, [SoMMark]) {
        #if canImport(CoreGraphics) && canImport(AppKit)
        let width = image.width
        let height = image.height
        let pixelSize = CGSize(width: Double(width), height: Double(height))

        // 1) Mark rect'lerini hesapla — off-screen olanlar filtrelenir, kalanlar
        //    1-bazlı sıralı renumber edilir. Vision model "1", "2", "3" görür
        //    (caller'ın input array'inde delik olsa bile). Caller orijinal
        //    element'e erişmek için `SoMMark.element` field'ını kullanır.
        var marks: [SoMMark] = []
        var rects: [CGRect] = []
        var visibleIndex = 0
        for element in elements {
            guard let rect = MarkLayout.computeMarkRect(
                elementFrame: element.frame.cgRect,
                imageScreenOrigin: imageScreenOrigin,
                imageLogicalSize: imageLogicalSize,
                imagePixelSize: pixelSize
            ) else { continue }
            visibleIndex += 1
            let mark = SoMMark(
                id: String(visibleIndex),
                element: element,
                frameInImage: CGRectBox(rect)
            )
            marks.append(mark)
            rects.append(rect)
        }

        // 2) Bitmap context — top-left convention için CTM flip
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,  // auto
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ComputerUseError.screenshotFailed(reason: "SoM: CGContext oluşturulamadı")
        }

        // CGContext bottom-left; CGImage data top-left → flip ile uyumla
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CTM hâlâ flipped — sonraki tüm çizimler top-left convention'da
        // (rect.origin.x soldan, rect.origin.y yukarıdan).

        // 3) Outline + badge çiz
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        defer { NSGraphicsContext.restoreGraphicsState() }

        let badgeSize = CGFloat(options.badgeSize)
        let outlineWidth = CGFloat(options.outlineWidth)
        let textNSColor = NSColor(
            srgbRed: CGFloat(options.textColor.red),
            green: CGFloat(options.textColor.green),
            blue: CGFloat(options.textColor.blue),
            alpha: CGFloat(options.textColor.alpha)
        )

        for (i, mark) in marks.enumerated() {
            let color = options.palette[i % options.palette.count].cgColor
            let rect = rects[i]

            // Outline
            context.setStrokeColor(color)
            context.setLineWidth(outlineWidth)
            context.stroke(rect)

            // **Faz 5 (v0.2.38):** Badge konumu BadgeLayout helper'ından —
            // content-aware placement (.smartCorner image kenarına göre seçer).
            // Clamping/bounds dışı kontrolü helper içinde; nil dönerse skip
            // (defansif — MarkLayout zaten görünür element'leri filtreliyor).
            guard let badgeRect = BadgeLayout.computeBadgeRect(
                elementRect: rect,
                badgeSize: badgeSize,
                imagePixelSize: pixelSize,
                placement: options.badgePlacement
            ) else { continue }
            context.setFillColor(color)
            context.fillEllipse(in: badgeRect)

            // Number — NSAttributedString tek karakter veya çift; merkezde
            let font = NSFont.boldSystemFont(ofSize: CGFloat(options.fontSize))
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textNSColor,
            ]
            let str = NSAttributedString(string: mark.id, attributes: textAttrs)
            let textSize = str.size()
            let textPoint = CGPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            str.draw(at: textPoint)
        }

        guard let result = context.makeImage() else {
            throw ComputerUseError.screenshotFailed(reason: "SoM: CGContext.makeImage başarısız")
        }
        return (result, marks)
        #else
        throw ComputerUseError.unsupported(reason: "SoM rendering yalnızca macOS'ta")
        #endif
    }
}
