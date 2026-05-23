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

    /// Birden fazla element için palette'ten döngüsel renk seçimi.
    /// 5 renk × yüksek alpha → vision model net algılar; arka plana boğulmaz.
    private static let palette: [CGColor] = [
        CGColor(red: 1.00, green: 0.20, blue: 0.20, alpha: 0.90),  // kırmızı
        CGColor(red: 0.20, green: 0.60, blue: 1.00, alpha: 0.90),  // mavi
        CGColor(red: 0.20, green: 0.80, blue: 0.30, alpha: 0.90),  // yeşil
        CGColor(red: 1.00, green: 0.70, blue: 0.00, alpha: 0.90),  // turuncu
        CGColor(red: 0.85, green: 0.30, blue: 0.95, alpha: 0.90),  // mor
    ]

    /// Outline stroke kalınlığı (pixel) ve badge boyutu — annotated PNG'nin
    /// vision model tarafından okunabilir olması için tipik retina capture'da
    /// (1600×1200) iyi çalışan değerler. Daha küçük image'da scale-down zaten
    /// vision model tarafından handle edilir.
    private static let outlineWidth: CGFloat = 4
    private static let badgeSize: CGFloat = 36

    /// Annotation entry point. Image üzerine N element için marker overlay'i çizer.
    ///
    /// - `image`: SCScreenshotManager çıktısı.
    /// - `elements`: işaretlenecek `UIElement` listesi (caller'ın `ui_query` sonucu).
    /// - `imageScreenOrigin`: image'in temsil ettiği bölgenin top-left logical
    ///   screen origin'i (window.frame.origin + opsiyonel titlebarOffset).
    /// - `imageLogicalSize`: bölgenin logical points cinsinden boyutu.
    /// - Returns: `(annotated CGImage, [SoMMark] in 1-bazlı ID sırasıyla)`.
    ///   Off-screen element'ler atlanır → `marks.count` ≤ `elements.count`.
    static func annotate(
        image: CGImage,
        elements: [UIElement],
        imageScreenOrigin: CGPoint,
        imageLogicalSize: CGSize
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

        for (i, mark) in marks.enumerated() {
            let color = palette[i % palette.count]
            let rect = rects[i]

            // Outline
            context.setStrokeColor(color)
            context.setLineWidth(outlineWidth)
            context.stroke(rect)

            // Badge: outline'ın sol-üst köşesinde dolu daire
            let badgeRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: badgeSize,
                height: badgeSize
            )
            context.setFillColor(color)
            context.fillEllipse(in: badgeRect)

            // Number — NSAttributedString tek karakter veya çift; merkezde
            let font = NSFont.boldSystemFont(ofSize: 20)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
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
