// App/Sources/Capture/CaptureOverlayWindow.swift
import AppKit
import CaptureKit

@MainActor
final class CaptureOverlayWindow: NSPanel {
    var onAreaSelected: ((CGRect, NSScreen) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancelled: (() -> Void)?

    private var overlayView: CaptureOverlayView!
    private var escMonitor: Any?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovable = false
        self.acceptsMouseMovedEvents = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false

        // Prevent this window from causing app activation changes.
        // Same technique used by CleanShot X's Freezer class.
        let preventsActivationSel = NSSelectorFromString("_setPreventsActivation:")
        if responds(to: preventsActivationSel) {
            perform(preventsActivationSel, with: NSNumber(value: true))
        }

        overlayView = CaptureOverlayView(frame: screen.frame)
        overlayView.onSelectionComplete = { [weak self] rect in
            guard let self, let screen = self.screen else { return }
            self.onAreaSelected?(rect, screen)
        }
        overlayView.onWindowSelected = { [weak self] windowID in
            self?.onWindowSelected?(windowID)
        }
        overlayView.onCancel = { [weak self] in
            self?.onCancelled?()
        }

        self.contentView = overlayView
    }

    // Don't become main window — reduces activation side effects
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func activate(mode: CaptureOverlayMode = .area) {
        orderFrontRegardless()
        overlayView.setMode(mode)
        overlayView.resetSelection()

        // Handle keyboard (ESC) via event monitor instead of first responder,
        // so we don't need to make the window key
        installEscMonitor()
    }

    func setFrozenBackground(_ image: CGImage) {
        overlayView.frozenBackground = image
    }

    func deactivate() {
        overlayView.restoreCursorIfNeeded()
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        orderOut(nil)
    }

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.onCancelled?()
                return nil
            }
            return event
        }
    }
}
