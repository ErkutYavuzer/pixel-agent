import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

/// ScreenCaptureKit (`SCScreenshotManager`) üzerinden tek-atımlık ekran/pencere
/// görüntüsü. macOS 14+ — pixel-agent platform target ile uyumlu.
///
/// `ScreenshotResult.pngData` PNG-encoded. MCP üzerinden base64'lenir.
public enum ScreenshotCapture {

    public static func capture(
        target: ScreenshotTarget,
        annotating elements: [UIElement] = [],
        options: SoMOptions = .default
    ) async throws -> ScreenshotResult {
        #if canImport(ScreenCaptureKit) && canImport(AppKit) && canImport(ImageIO)
        let content = try await fetchContent()

        let (filter, logicalFrame, bundleID, titlebarOffset) = try resolve(target: target, content: content)
        let config = SCStreamConfiguration()
        config.width = Int(logicalFrame.width)
        config.height = Int(logicalFrame.height)
        config.showsCursor = false
        config.captureResolution = .best

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            throw ComputerUseError.screenshotFailed(reason: "SCScreenshotManager: \(error.localizedDescription)")
        }

        // **Faz 3c (ADR-0030):** `.windowContent` ise titlebar'ı kes.
        let croppedImage: CGImage
        let croppedLogicalFrame: CGRect
        if let offset = titlebarOffset, offset > 0 {
            guard let cropRect = WindowCrop.computeCropRect(
                imageWidth: cgImage.width,
                imageHeight: cgImage.height,
                windowWidth: logicalFrame.width,
                windowHeight: logicalFrame.height,
                titlebarOffsetPoints: offset
            ), let cropped = cgImage.cropping(to: cropRect) else {
                throw ComputerUseError.screenshotFailed(
                    reason: "Titlebar crop hesabı başarısız (offset=\(offset)pt, window=\(logicalFrame.size))"
                )
            }
            croppedImage = cropped
            croppedLogicalFrame = WindowCrop.computeLogicalFrame(
                windowFrame: logicalFrame,
                titlebarOffsetPoints: offset
            )
        } else {
            croppedImage = cgImage
            croppedLogicalFrame = logicalFrame
        }

        // **Faz 4 (ADR-0031):** `elements` doluysa Set-of-Mark overlay çiz.
        // **Faz 5c (v0.2.51):** Eğer `options.badgePlacement == .contentAware`
        // ise OCR upfront — text region'larını çıkar, SoMRenderer'a passla.
        // OCR async; başarısız olursa boş array (SoMRenderer .labelAware
        // fallback'ine düşer).
        // **Faz 5c follow-up (v0.2.52):** `options.ocrCropMode` ile
        // `.wholeImage` (tek pass, default) veya `.perElement` (her element
        // için crop edilmiş region'da ayrı pass) seçimi.
        let finalImage: CGImage
        let marks: [SoMMark]
        if !elements.isEmpty {
            let textRegions: [CGRect]
            if options.badgePlacement == .contentAware {
                textRegions = await collectTextRegions(
                    for: elements,
                    in: croppedImage,
                    options: options,
                    imageScreenOrigin: croppedLogicalFrame.origin,
                    imageLogicalSize: croppedLogicalFrame.size
                )
            } else {
                textRegions = []
            }
            let (annotated, generated) = try SoMRenderer.annotate(
                image: croppedImage,
                elements: elements,
                imageScreenOrigin: croppedLogicalFrame.origin,
                imageLogicalSize: croppedLogicalFrame.size,
                options: options,
                textRegions: textRegions
            )
            finalImage = annotated
            marks = generated
        } else {
            finalImage = croppedImage
            marks = []
        }

        let pngData = try encodePNG(finalImage)
        return ScreenshotResult(
            pngData: pngData,
            pixelWidth: finalImage.width,
            pixelHeight: finalImage.height,
            logicalFrame: CGRectBox(croppedLogicalFrame),
            bundleID: bundleID,
            marks: marks
        )
        #else
        throw ComputerUseError.unsupported(reason: "ScreenCaptureKit yok (macOS 14+ gerekli)")
        #endif
    }

    #if canImport(ScreenCaptureKit) && canImport(AppKit)

    /// **Faz 5c follow-up (v0.2.52):** OCR text region toplama strateji
    /// dispatcher. `options.ocrCropMode`'a göre:
    /// - `.wholeImage`: tek Vision pass tüm image üzerinde (Sprint 26 path).
    /// - `.perElement`: her element için `ElementRegionExpander`
    ///   ile crop edilmiş region'da ayrı pass. Sonuçlar union'lanır
    ///   (deduplication yok — SoMRenderer scoring CGRect overlap'le iş
    ///   görür, duplicate region'lar score'u şişirmez çünkü `min` arama
    ///   yapılır, tüm adayların score'u eşit oranda etkilenir).
    private static func collectTextRegions(
        for elements: [UIElement],
        in image: CGImage,
        options: SoMOptions,
        imageScreenOrigin: CGPoint,
        imageLogicalSize: CGSize
    ) async -> [CGRect] {
        switch options.ocrCropMode {
        case .wholeImage:
            return await OCRTextDetector.detectTextRegions(in: image)
        case .perElement:
            let pixelSize = CGSize(width: Double(image.width), height: Double(image.height))
            let badgeSize = CGFloat(options.badgeSize)
            var union: [CGRect] = []
            for element in elements {
                // MarkLayout ile element image içindeki konumunu hesapla
                // (SoMRenderer'ın yaptığı dönüşümün aynısı).
                guard let elementRectInImage = MarkLayout.computeMarkRect(
                    elementFrame: element.frame.cgRect,
                    imageScreenOrigin: imageScreenOrigin,
                    imageLogicalSize: imageLogicalSize,
                    imagePixelSize: pixelSize
                ) else { continue }
                guard let cropRect = ElementRegionExpander.expandedRect(
                    elementRect: elementRectInImage,
                    badgeSize: badgeSize,
                    imagePixelSize: pixelSize
                ) else { continue }
                let regions = await OCRTextDetector.detectTextRegions(in: image, cropRect: cropRect)
                union.append(contentsOf: regions)
            }
            return union
        }
    }

    private static func fetchContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ComputerUseError.screenshotFailed(reason: "SCShareableContent: \(error.localizedDescription)")
        }
    }

    /// `ScreenshotTarget` → `SCContentFilter` + logical frame + bundleID + (Faz 3c)
    /// opsiyonel titlebarOffset. Hata durumunda `screenshotFailed`.
    private static func resolve(
        target: ScreenshotTarget,
        content: SCShareableContent
    ) throws -> (SCContentFilter, CGRect, String?, Double?) {
        switch target {
        case .allDisplays, .activeDisplay:
            // Aktif display: frontmost app'ın bulunduğu display (yoksa ilk).
            let display: SCDisplay
            if case .activeDisplay = target,
               let app = NSWorkspace.shared.frontmostApplication,
               let pidDisplay = displayForApp(pid: app.processIdentifier, content: content) {
                display = pidDisplay
            } else if let first = content.displays.first {
                display = first
            } else {
                throw ComputerUseError.screenshotFailed(reason: "Display yok")
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let frame = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            return (filter, frame, nil, nil)

        case .window(let bundleID):
            guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID }) else {
                throw ComputerUseError.screenshotFailed(reason: "BundleID için pencere yok: \(bundleID)")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return (filter, window.frame, bundleID, nil)

        case .windowContent(let bundleID, let titlebarOffset):
            guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID }) else {
                throw ComputerUseError.screenshotFailed(reason: "BundleID için pencere yok: \(bundleID)")
            }
            guard titlebarOffset >= 0, titlebarOffset < window.frame.height else {
                throw ComputerUseError.screenshotFailed(
                    reason: "titlebar_offset (\(titlebarOffset)pt) pencere yüksekliği (\(window.frame.height)pt) içinde olmalı"
                )
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return (filter, window.frame, bundleID, titlebarOffset)
        }
    }

    private static func displayForApp(pid: pid_t, content: SCShareableContent) -> SCDisplay? {
        // App'in herhangi bir window'unun bulunduğu display'i bul.
        let appWindows = content.windows.filter { $0.owningApplication?.processID == pid }
        guard let frame = appWindows.first?.frame else { return nil }
        return content.displays.first { display in
            CGRect(x: 0, y: 0, width: display.width, height: display.height).intersects(frame)
        }
    }
    #endif

    // MARK: - PNG encoding

    #if canImport(ImageIO)
    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ComputerUseError.screenshotFailed(reason: "CGImageDestination oluşturulamadı")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ComputerUseError.screenshotFailed(reason: "PNG encode başarısız")
        }
        return data as Data
    }
    #endif
}
