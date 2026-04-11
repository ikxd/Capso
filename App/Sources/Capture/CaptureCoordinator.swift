// App/Sources/Capture/CaptureCoordinator.swift
import AppKit
import CoreImage
import Observation
import AnnotationKit
import CaptureKit
import OCRKit
import SharedKit

@MainActor
@Observable
final class CaptureCoordinator {
    private let settings: AppSettings
    private var overlayWindows: [CaptureOverlayWindow] = []
    /// Stack of active preview windows:
    /// - `[0]` is the OLDEST preview, anchored at the bottom-left primary slot
    /// - `[N]` is the NEWEST preview, sitting at the top of the visual stack
    /// - New captures append to the end, growing the stack upward
    /// - When the stack overflows, `[0]` (the oldest) slides off-screen to
    ///   the left and the rest shift down one slot
    private var quickAccessWindows: [QuickAccessWindow] = []
    /// Maximum previews kept on-screen. Oldest is evicted when exceeded.
    private let maxQuickAccessStackSize = 5
    private var annotationWindow: AnnotationEditorWindow?
    private var pinnedControllers: [PinnedScreenshotController] = []

    var lastCaptureResult: CaptureResult?
    var ocrCoordinator: OCRCoordinator?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func captureArea() {
        // Small delay to let the menu bar dropdown fully dismiss
        // before showing the capture overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showOverlay()
        }
    }

    func captureFullscreen() {
        // Capture the display the user is currently looking at (the one
        // containing the mouse cursor), not unconditionally the primary.
        // For keyboard-shortcut invocations this matches where attention is;
        // for menu-bar clicks the mouse is on the screen whose menu bar was
        // clicked. Fall back to `NSScreen.main` then the primary CGDisplay
        // so we never end up with no target at all.
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        let displayID = targetScreen?.displayID ?? CGMainDisplayID()
        Task {
            do {
                let result = try await ScreenCaptureManager.captureFullscreen(displayID: displayID)
                handleCaptureResult(result)
            } catch {
                print("Fullscreen capture failed: \(error)")
            }
        }
    }

    func captureWindow() {
        // Enumerate windows first, then show overlay in window selection mode
        Task {
            do {
                // Exclude only Capso's overlay windows (not all Capso windows
                // like Settings) so the user can still capture them.
                let overlayIDs = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
                let windows = try await ContentEnumerator.windows()
                    .filter { !overlayIDs.contains($0.id) }

                guard !windows.isEmpty else {
                    print("No windows found to capture")
                    return
                }

                showOverlay(mode: .windowSelection(windows))
            } catch {
                print("Window enumeration failed: \(error)")
            }
        }
    }

    private func showOverlay(mode: CaptureOverlayMode = .area) {
        dismissOverlay()
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(screen: screen)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                self?.performAreaCapture(rect: rect, screen: screen)
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                self?.performWindowCapture(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.dismissOverlay()
            }
            overlay.activate(mode: mode)
            overlayWindows.append(overlay)
        }
    }

    private func performWindowCapture(windowID: CGWindowID) {
        Task {
            do {
                // Always capture without system shadow — we generate our own
                // uniform padding + frosted glass backdrop when the setting is on.
                let result = try await ScreenCaptureManager.captureWindow(
                    windowID: windowID,
                    includeShadow: false
                )
                if settings.captureWindowShadow {
                    // Capture the real desktop behind the window (excluding the
                    // window itself) for the frosted glass background.
                    // Padding = 4% of the shorter side, plus room for shadow blur.
                    let shorter = min(CGFloat(result.image.width), CGFloat(result.image.height))
                    let padding = max(30, shorter * 0.04)
                    let totalPadding = padding + 20 // extra for shadow spread
                    let desktopBg = try await ScreenCaptureManager.captureDesktopBehindWindow(
                        windowID: windowID,
                        padding: totalPadding
                    )
                    if let composited = Self.compositeWindowWithFrostedGlass(
                        windowImage: result.image,
                        desktopBackground: desktopBg
                    ) {
                        let enhanced = CaptureResult(
                            image: composited,
                            mode: result.mode,
                            captureRect: result.captureRect,
                            windowName: result.windowName,
                            appName: result.appName,
                            timestamp: result.timestamp,
                            displayID: result.displayID
                        )
                        handleCaptureResult(enhanced)
                        return
                    }
                }
                handleCaptureResult(result)
            } catch {
                print("Window capture failed: \(error)")
            }
        }
    }

    /// Composite a window screenshot over a frosted-glass version of the real
    /// desktop background, with uniform padding, rounded corners, and a soft
    /// drop shadow.
    private static func compositeWindowWithFrostedGlass(
        windowImage: CGImage,
        desktopBackground: CGImage
    ) -> CGImage? {
        let outW = desktopBackground.width
        let outH = desktopBackground.height
        guard outW > 0, outH > 0 else { return nil }

        let imgW = CGFloat(windowImage.width)
        let imgH = CGFloat(windowImage.height)
        let canvasSize = CGSize(width: outW, height: outH)
        let shadowRadius: CGFloat = 20
        let cornerRadius: CGFloat = 12

        // Centre the window in the canvas
        let offsetX = (CGFloat(outW) - imgW) / 2
        let offsetY = (CGFloat(outH) - imgH) / 2
        let imageRect = CGRect(x: offsetX, y: offsetY, width: imgW, height: imgH)
        let roundedPath = CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // --- Blur the desktop background via CoreImage ---
        guard let backdrop = frostedGlassBackdrop(from: desktopBackground, targetSize: canvasSize) else { return nil }

        // --- Composite ---
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvasRect = CGRect(x: 0, y: 0, width: outW, height: outH)

        // 1. Draw frosted desktop backdrop
        ctx.draw(backdrop, in: canvasRect)

        // 2. Draw soft shadow — clip to OUTSIDE the rounded rect so the
        //    white fill used to generate the shadow never bleeds into the
        //    corner area (which would show as white corner artifacts).
        ctx.saveGState()
        let outerPath = CGMutablePath()
        outerPath.addRect(canvasRect)
        outerPath.addPath(roundedPath)
        ctx.addPath(outerPath)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: shadowRadius,
            color: NSColor.black.withAlphaComponent(0.25).cgColor
        )
        ctx.addPath(roundedPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 3. Draw window clipped to rounded corners
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        ctx.draw(windowImage, in: imageRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Blur and slightly saturate a desktop background image for the frosted
    /// glass effect behind window captures.
    private static func frostedGlassBackdrop(from image: CGImage, targetSize: CGSize) -> CGImage? {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        guard srcW > 0, srcH > 0 else { return nil }

        var ci = CIImage(cgImage: image)

        // Aspect-fill to target size with slight overshoot to avoid blur edges.
        let coverScale = max(targetSize.width / srcW, targetSize.height / srcH) * 1.05
        ci = ci.transformed(by: CGAffineTransform(scaleX: coverScale, y: coverScale))
        let tx = (targetSize.width - ci.extent.width) / 2 - ci.extent.minX
        let ty = (targetSize.height - ci.extent.height) / 2 - ci.extent.minY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation slightly for richer colours.
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.4,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.98,
        ]), let out = f.outputImage {
            ci = out
        }

        // Heavy Gaussian blur for frosted glass look.
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 80.0,
        ]), let out = f.outputImage {
            ci = out
        }

        let ciCtx = CIContext(options: nil)
        return ciCtx.createCGImage(ci, from: CGRect(origin: .zero, size: targetSize))
    }

    private func dismissOverlay() {
        for window in overlayWindows {
            window.deactivate()
        }
        overlayWindows.removeAll()
    }

    private func performAreaCapture(rect: CGRect, screen: NSScreen) {
        Task {
            do {
                let screenFrame = screen.frame
                // rect is already in view-local coords (0..screenWidth, 0..screenHeight, bottom-left origin)
                // Only flip Y for ScreenCaptureKit (top-left origin)
                let screenRect = CGRect(
                    x: rect.origin.x,
                    y: screenFrame.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                let displayID = screen.displayID
                let result = try await ScreenCaptureManager.captureArea(
                    rect: screenRect,
                    displayID: displayID
                )
                handleCaptureResult(result)
            } catch {
                print("Area capture failed: \(error)")
            }
        }
    }

    private func handleCaptureResult(_ result: CaptureResult) {
        lastCaptureResult = result
        if settings.playShutterSound {
            Self.shutterSound?.stop()
            Self.shutterSound?.play()
        }
        if settings.screenshotAutoCopy {
            copyImageToClipboard(result.image)
        }
        if settings.screenshotAutoSave {
            saveImageToFile(result.image)
        }
        if settings.screenshotShowPreview {
            showQuickAccess(for: result)
        }
    }

    /// The real camera-shutter sound macOS itself plays for Cmd+Shift+3/4.
    /// Loaded from the built-in CoreAudio system sounds bundle. If the file
    /// ever moves or is renamed in a future macOS release we fall back to a
    /// subtler "Pop" alert sound (which is at least not the "Tink" error
    /// ding we used to use).
    private static let shutterSound: NSSound? = {
        let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: shutterPath),
           let sound = NSSound(contentsOf: URL(fileURLWithPath: shutterPath), byReference: true) {
            return sound
        }
        return NSSound(named: "Pop")
    }()

    private func showQuickAccess(for result: CaptureResult) {
        // If the stack is full, evict the oldest (the one anchored at the
        // bottom slot) with a slide-off-left animation. The remaining
        // previews will slide down one slot as part of the restack below.
        while quickAccessWindows.count >= maxQuickAccessStackSize {
            let oldest = quickAccessWindows.removeFirst()
            oldest.slideOffLeftAndClose()
        }

        let captureScreen = NSScreen.screens.first { $0.displayID == result.displayID }
        let window = QuickAccessWindow(result: result, settings: settings, screen: captureScreen)

        // All callbacks capture the specific `window` weakly so the right
        // stack slot gets dismissed — not whichever one happens to be newest.
        window.onCopy = { [weak self, weak window] in
            guard let self, let window else { return }
            self.copyImageToClipboard(result.image)
            self.dismissQuickAccessWindow(window)
        }
        window.onSave = { [weak self, weak window] in
            guard let self, let window else { return }
            self.saveImageToFile(result.image)
            self.dismissQuickAccessWindow(window)
        }
        window.onAnnotate = { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismissQuickAccessWindow(window)
            self.openAnnotationEditor(result)
        }
        window.onPin = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.frame
            self.dismissQuickAccessWindow(window)
            self.pinToScreen(result, anchor: anchor)
        }
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismissQuickAccessWindow(window)
        }

        quickAccessWindows.append(window)
        restackQuickAccessWindows(excluding: window)
        window.show()
    }

    /// Remove a specific preview from the stack and close it, then slide the
    /// remaining previews on the same screen down to collapse the gap.
    private func dismissQuickAccessWindow(_ window: QuickAccessWindow) {
        guard let idx = quickAccessWindows.firstIndex(where: { $0 === window }) else {
            return
        }
        quickAccessWindows.remove(at: idx)
        window.close()
        restackQuickAccessWindows()
    }

    /// Reposition all preview windows using per-screen stacking: windows on
    /// the same screen share a stack (index 0 at the bottom, 1 above it, …),
    /// independent of windows on other screens.
    ///
    /// - Parameter skipAnimation: A window to position without animation
    ///   (used for the newly-created preview so it appears at the correct
    ///   slot immediately before its show() fade-in).
    private func restackQuickAccessWindows(excluding skipAnimation: QuickAccessWindow? = nil) {
        // Group windows by their target screen's displayID, preserving order
        // (oldest → newest within each group) so the oldest sits at index 0.
        var perScreen: [CGDirectDisplayID: [QuickAccessWindow]] = [:]
        for win in quickAccessWindows {
            let id = win.targetScreen.displayID
            perScreen[id, default: []].append(win)
        }
        for (_, windows) in perScreen {
            for (i, win) in windows.enumerated() {
                let animated = (win !== skipAnimation)
                win.repositionForStackIndex(i, animated: animated)
            }
        }
    }

    private func openAnnotationEditor(_ result: CaptureResult) {
        annotationWindow = AnnotationEditorWindow(
            image: result.image,
            onSave: { [weak self] (rendered: CGImage) in
                self?.saveRenderedImage(rendered)
                self?.annotationWindow = nil
            },
            onCopy: { [weak self] (rendered: CGImage) in
                self?.copyRenderedImage(rendered)
                self?.annotationWindow = nil
            },
            onClose: { [weak self] in
                self?.annotationWindow = nil
            }
        )
        annotationWindow?.show()
    }

    private func pinToScreen(_ result: CaptureResult, anchor: CGRect) {
        let controller = PinnedScreenshotController(
            image: result.image,
            anchorRect: anchor,
            onCopy: { [weak self] in
                self?.copyImageToClipboard(result.image)
            },
            onSave: { [weak self] in
                self?.saveImageToFile(result.image)
            },
            onDidClose: { [weak self] controllerID in
                self?.pinnedControllers.removeAll { $0.id == controllerID }
            }
        )
        pinnedControllers.append(controller)
        controller.show()
    }

    private func copyImageToClipboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.writeObjects([nsImage])
    }

    private func saveImageToFile(_ image: CGImage) {
        let format = settings.screenshotFormat
        let fileFormat: FileFormat = format == .png ? .png : .jpeg
        let url = FileNaming.generateFileURL(
            in: settings.exportLocation,
            type: .screenshot,
            format: fileFormat
        )
        let data: Data? = switch format {
        case .png: ImageUtilities.pngData(from: image)
        case .jpeg: ImageUtilities.jpegData(from: image)
        }
        if let data { try? data.write(to: url) }
    }

    private func saveRenderedImage(_ image: CGImage) {
        saveImageToFile(image)
    }

    private func copyRenderedImage(_ image: CGImage) {
        copyImageToClipboard(image)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}
