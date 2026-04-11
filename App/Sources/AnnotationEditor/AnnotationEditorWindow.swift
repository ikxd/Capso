// App/Sources/AnnotationEditor/AnnotationEditorWindow.swift
import AppKit
import SwiftUI
import AnnotationKit

@MainActor
final class AnnotationEditorWindow: NSPanel {
    private let document: AnnotationDocument

    init(
        image: CGImage,
        onSave: @escaping (CGImage) -> Void,
        onCopy: @escaping (CGImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        self.document = AnnotationDocument(imageSize: CGSize(width: imgW, height: imgH))

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let maxW = screen.visibleFrame.width * 0.8
        let maxH = screen.visibleFrame.height * 0.8
        let chromeH: CGFloat = 110

        let scale = min(1.0, min(maxW / imgW, (maxH - chromeH) / imgH))
        let winW = imgW * scale
        let winH = imgH * scale + chromeH

        let x = screen.visibleFrame.midX - winW / 2
        let y = screen.visibleFrame.midY - winH / 2

        super.init(
            contentRect: NSRect(x: x, y: y, width: winW, height: winH),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Annotate"
        self.isReleasedWhenClosed = false
        // Use .normal level so the window stays visible when app loses focus
        self.level = .normal
        // Ensure tooltip tracking and key-window behaviour work correctly.
        self.becomesKeyOnlyIfNeeded = false
        self.acceptsMouseMovedEvents = true

        let view = AnnotationEditorView(
            sourceImage: image,
            document: document,
            onSave: { [weak self] rendered in
                onSave(rendered)
                self?.close()
            },
            onCopy: { [weak self] rendered in
                onCopy(rendered)
                self?.close()
            },
            onCancel: { [weak self] in
                onClose()
                self?.close()
            }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
