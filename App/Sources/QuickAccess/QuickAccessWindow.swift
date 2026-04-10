// App/Sources/QuickAccess/QuickAccessWindow.swift
import AppKit
import SwiftUI
import CaptureKit
import SharedKit

@MainActor
final class QuickAccessWindow: NSPanel {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onAnnotate: (() -> Void)?
    var onPin: (() -> Void)?
    var onClose: (() -> Void)?

    private var autoDismissTimer: Timer?
    private let settings: AppSettings
    /// The screen this preview is anchored to (where the capture originated).
    let targetScreen: NSScreen

    init(result: CaptureResult, settings: AppSettings, screen: NSScreen?) {
        self.settings = settings
        self.targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!

        let windowWidth: CGFloat = 336
        let windowHeight: CGFloat = 172

        let screenFrame = targetScreen.visibleFrame
        let x: CGFloat = switch settings.quickAccessPosition {
        case .bottomLeft: screenFrame.minX + 16
        case .bottomRight: screenFrame.maxX - windowWidth - 16
        }
        let y = screenFrame.minY + 16

        let contentRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow
        // NSPanel defaults hidesOnDeactivate to true, which causes the preview
        // to be auto-hidden the moment Capso loses focus (e.g. right after the
        // captured window's app becomes active after Capture Window). That's
        // why the preview "only reappears when you start the next capture" —
        // the next overlay reactivates Capso, which restores the hidden panel.
        self.hidesOnDeactivate = false

        let nsImage = NSImage(cgImage: result.image, size: NSSize(
            width: result.image.width, height: result.image.height
        ))

        let view = QuickAccessView(
            thumbnail: nsImage,
            onCopy: { [weak self] in self?.onCopy?() },
            onSave: { [weak self] in self?.onSave?() },
            onAnnotate: { [weak self] in self?.onAnnotate?() },
            onPin: { [weak self] in self?.onPin?() },
            onClose: { [weak self] in self?.onClose?() }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.y -= 20
        setFrame(startFrame, display: false)
        alphaValue = 0

        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1
        }

        if settings.quickAccessAutoClose {
            autoDismissTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(settings.quickAccessAutoCloseInterval),
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onClose?()
                }
            }
        }
    }

    override func close() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    /// Evict this preview off-screen to the left with a slide animation.
    /// Used when the preview stack overflows (the oldest one is pushed out
    /// of the bottom slot to make room for new captures above).
    func slideOffLeftAndClose() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        var target = frame
        target.origin.x = -(target.width + 40)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(target, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Bypass the close() override — we already ran our own exit
            // animation and don't want a second fade on top of it.
            self?.orderOut(nil)
        })
    }

    /// Spacing between stacked preview windows.
    private static let stackSpacing: CGFloat = 12

    /// Animate (or directly set) this window's y-position so it occupies the
    /// given slot in the preview stack. Index 0 is the bottom-most slot
    /// (primary position, same as a single preview), index 1 sits right above
    /// it, and so on.
    ///
    /// X position is re-read from `settings.quickAccessPosition` so that if
    /// the user changes "bottom-left" ⇄ "bottom-right" between captures the
    /// stack still lines up correctly on the next reposition.
    func repositionForStackIndex(_ index: Int, animated: Bool = true) {
        let screenFrame = targetScreen.visibleFrame
        let windowWidth = frame.width
        let windowHeight = frame.height
        let x: CGFloat = switch settings.quickAccessPosition {
        case .bottomLeft: screenFrame.minX + 16
        case .bottomRight: screenFrame.maxX - windowWidth - 16
        }
        let baseY = screenFrame.minY + 16
        let y = baseY + CGFloat(index) * (windowHeight + Self.stackSpacing)
        let newFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }
}
