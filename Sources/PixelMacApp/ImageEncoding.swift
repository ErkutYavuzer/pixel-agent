import AppKit
import Foundation

/// Mac → iOS dashboard ekran resmi push'unda PNG payload'unu JPEG'e sıkıştırır.
/// Bandwidth tasarrufu için varsayılan kalite 0.5; bozulma payloads'ta tolere edilir
/// (önizleme amaçlı). PNG decode başarısız ise `nil` döner.
enum ImageEncoding {
    static func compressPNGToJPEG(data: Data, quality: CGFloat = 0.5) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
