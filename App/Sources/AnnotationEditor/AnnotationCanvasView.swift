// App/Sources/AnnotationEditor/AnnotationCanvasView.swift
import SwiftUI
import AppKit
import AnnotationKit

struct AnnotationCanvasView: NSViewRepresentable {
    let document: AnnotationDocument
    let sourceImage: CGImage
    let currentTool: AnnotationTool
    let currentStyle: AnnotationKit.StrokeStyle
    let zoomScale: CGFloat
    let refreshTrigger: Int
    var onSwitchToSelect: (() -> Void)?

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView()
        view.document = document
        view.sourceImage = sourceImage
        view.currentTool = currentTool
        view.currentStyle = currentStyle
        view.zoomScale = zoomScale
        view.onObjectCreated = {
            if currentTool != .counter {
                onSwitchToSelect?()
            }
        }
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        let toolChanged = nsView.currentTool != currentTool
        nsView.currentTool = currentTool
        nsView.currentStyle = currentStyle
        nsView.zoomScale = zoomScale
        nsView.onObjectCreated = {
            if currentTool != .counter {
                onSwitchToSelect?()
            }
        }
        nsView.needsDisplay = true
        if toolChanged {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }
}
