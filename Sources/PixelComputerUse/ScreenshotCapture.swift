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
enum ScreenshotCapture {

    static func capture(
        target: ScreenshotTarget,
        annotating elements: [UIElement] = []
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
        let finalImage: CGImage
        let marks: [SoMMark]
        if !elements.isEmpty {
            let (annotated, generated) = try SoMRenderer.annotate(
                image: croppedImage,
                elements: elements,
                imageScreenOrigin: croppedLogicalFrame.origin,
                imageLogicalSize: croppedLogicalFrame.size
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
