import CoreGraphics
import PixelComputerUse

/// `SoMMark.frameInImage` (annotated PNG pixel space) → SwiftUI view-space
/// (point) dönüşümü için saf yardımcı (C2/C3).
///
/// `InlineScreenshotView` resmi `Image(...).resizable().aspectRatio(contentMode: .fit)`
/// ile sığdırır. Mark rect'leri pixel uzayında doğmuş olduğu için view
/// boyutuna oranlamak gerekiyor — bu fonksiyon o ölçeklemeyi yapıyor.
///
/// Saf — SwiftUI / NSImage'a bağımlı değil.
enum ScreenshotMarkLayout {

    /// Pixel rect'i view-space CGRect'e çevirir. Image aspect-fit ile çizildi
    /// varsayımı; yani view'in iç boyutu = image aspect oranını koruyan en
    /// büyük dikdörtgen. Çağıran bu fitted size'ı `viewSize` olarak verir.
    static func viewRect(
        forImageRect rect: CGRectBox,
        imagePixelSize: CGSize,
        viewSize: CGSize
    ) -> CGRect {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return .zero
        }
        let scaleX = viewSize.width / imagePixelSize.width
        let scaleY = viewSize.height / imagePixelSize.height
        return CGRect(
            x: rect.x * scaleX,
            y: rect.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }

    /// Verilen container `containerSize` içinde, image aspect oranını koruyan
    /// en büyük fitted size'ı (aspect-fit). View'in render alanını
    /// kareye benzemeyen container'da hesaplamak için.
    static func fittedSize(
        imagePixelSize: CGSize,
        containerSize: CGSize
    ) -> CGSize {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return .zero
        }
        let imageAspect = imagePixelSize.width / imagePixelSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            // Image daha geniş → genişliğe sığdır, height küçülür.
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image daha dar (veya eşit) → yüksekliğe sığdır.
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}
