import XCTest
import CoreGraphics

@testable import PixelComputerUse

/// **Faz 4 (ADR-0031):** `SoMRenderer.annotate` smoke testleri. CGContext +
/// NSGraphicsContext text drawing'in side-effect'leri pixel-by-pixel
/// karşılaştırılamaz; bu test'ler API kontratını (mark count, dimension
/// preservation, off-screen filter) doğrular.
final class SoMRendererTests: XCTestCase {

    /// Solid renkli bitmap CGImage üretir — gerçek SCScreenshotManager çıktısı
    /// yerine test mock'u olarak kullanılır.
    private func makeBlankImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeElement(
        title: String,
        frame: CGRect
    ) -> UIElement {
        UIElement(
            role: "AXButton",
            title: title,
            label: nil,
            identifier: nil,
            frame: CGRectBox(frame),
            bundleID: "com.example.App",
            path: ["AXApplication", "AXWindow", "AXButton"],
            opaqueID: "com.example.App|AXApplication|AXWindow|AXButton:\(title)"
        )
    }

    // MARK: - Smoke tests

    func testEmptyElementsProducesNoMarks() throws {
        let image = makeBlankImage(width: 800, height: 600)
        let (result, marks) = try SoMRenderer.annotate(
            image: image,
            elements: [],
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(marks.count, 0)
        // Image dimension preserved
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    func testThreeElementsProduceThreeMarks() throws {
        let image = makeBlankImage(width: 800, height: 600)
        let elements = [
            makeElement(title: "A", frame: CGRect(x: 50, y: 50, width: 100, height: 40)),
            makeElement(title: "B", frame: CGRect(x: 200, y: 100, width: 80, height: 40)),
            makeElement(title: "C", frame: CGRect(x: 300, y: 200, width: 120, height: 50)),
        ]
        let (_, marks) = try SoMRenderer.annotate(
            image: image,
            elements: elements,
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(marks.count, 3)
        XCTAssertEqual(marks[0].id, "1")
        XCTAssertEqual(marks[1].id, "2")
        XCTAssertEqual(marks[2].id, "3")
        XCTAssertEqual(marks[0].element.title, "A")
    }

    func testOffScreenElementSkipped() throws {
        let image = makeBlankImage(width: 800, height: 600)
        let elements = [
            makeElement(title: "InsideA", frame: CGRect(x: 100, y: 100, width: 50, height: 50)),
            // Tamamen sağ tarafta
            makeElement(title: "OffscreenRight", frame: CGRect(x: 1000, y: 100, width: 50, height: 50)),
            makeElement(title: "InsideB", frame: CGRect(x: 300, y: 200, width: 50, height: 50)),
        ]
        let (_, marks) = try SoMRenderer.annotate(
            image: image,
            elements: elements,
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(marks[0].element.title, "InsideA")
        XCTAssertEqual(marks[1].element.title, "InsideB")
        // IDs hâlâ orijinal input sırasına göre 1, 3 değil — atlanan yok sayılır,
        // 1-bazlı sıralama korunur (caller "1" ve "2" görür).
        // Implementation: id = String(visible_index + 1).
        XCTAssertEqual(marks[0].id, "1")
        XCTAssertEqual(marks[1].id, "2")
    }

    func testDimensionsPreservedAcrossAnnotation() throws {
        let image = makeBlankImage(width: 1600, height: 1144)  // 2x window_content
        let element = makeElement(title: "X", frame: CGRect(x: 100, y: 100, width: 50, height: 30))
        let (result, _) = try SoMRenderer.annotate(
            image: image,
            elements: [element],
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 572)
        )
        XCTAssertEqual(result.width, 1600)
        XCTAssertEqual(result.height, 1144)
    }

    func testMarkFrameInImageUsesPixelCoordinates() throws {
        // 2x retina: 800×600 logical → 1600×1200 pixel.
        // Element (100, 50, 40, 30) → pixel (200, 100, 80, 60).
        let image = makeBlankImage(width: 1600, height: 1200)
        let element = makeElement(title: "X", frame: CGRect(x: 100, y: 50, width: 40, height: 30))
        let (_, marks) = try SoMRenderer.annotate(
            image: image,
            elements: [element],
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].frameInImage.x, 200)
        XCTAssertEqual(marks[0].frameInImage.y, 100)
        XCTAssertEqual(marks[0].frameInImage.width, 80)
        XCTAssertEqual(marks[0].frameInImage.height, 60)
    }

    func testIDsAreOneBased() throws {
        let image = makeBlankImage(width: 800, height: 600)
        let elements = (0..<5).map { i in
            makeElement(
                title: "el\(i)",
                frame: CGRect(x: 50 + i * 100, y: 50, width: 50, height: 30)
            )
        }
        let (_, marks) = try SoMRenderer.annotate(
            image: image,
            elements: elements,
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(marks.map { $0.id }, ["1", "2", "3", "4", "5"])
    }
}
