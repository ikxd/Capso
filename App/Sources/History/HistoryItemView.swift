// App/Sources/History/HistoryItemView.swift
import SwiftUI
import HistoryKit

struct HistoryItemView: View {
    let entry: HistoryEntry
    let coordinator: HistoryCoordinator
    @State private var isHovered = false
    @State private var thumbnailImage: NSImage?

    private var modeBadge: (String, Color) {
        switch entry.captureMode {
        case .area: ("Area", .blue)
        case .fullscreen: ("Full", .blue)
        case .window: ("Window", .blue)
        case .recording: ("Video", .red)
        case .gif: ("GIF", .orange)
        }
    }

    private var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.createdAt, relativeTo: Date())
    }

    private var dimensionString: String {
        "\(entry.imageWidth) × \(entry.imageHeight)"
    }

    private var displayName: String {
        if let name = entry.sourceAppName, !name.isEmpty {
            return name
        }
        switch entry.captureMode {
        case .area: return String(localized: "Area Capture")
        case .fullscreen: return String(localized: "Fullscreen")
        case .window: return String(localized: "Window")
        case .recording: return String(localized: "Recording")
        case .gif: return String(localized: "GIF")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)

                // Mode badge
                let (label, color) = modeBadge
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)

                // Hover action buttons
                if isHovered {
                    HStack(spacing: 4) {
                        actionButton("doc.on.doc") { coordinator.copyToClipboard(entry) }
                        actionButton("square.and.arrow.down") { coordinator.saveToFile(entry) }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(isHovered ? 0.1 : 0.04), lineWidth: 0.5)
            )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(timeString)
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 2, height: 2)
                    Text(dimensionString)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .background(.white.opacity(isHovered ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(isHovered ? 0.1 : 0.04), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.2 : 0), radius: 8, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { loadThumbnail() }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(.quaternary.opacity(0.3))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.quaternary)
                }
        }
    }

    private func actionButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copy to Clipboard") { coordinator.copyToClipboard(entry) }
        Button("Save to...") { coordinator.saveToFile(entry) }
        Divider()
        Button("Show in Finder") { coordinator.showInFinder(entry) }
        Divider()
        Button("Delete from History", role: .destructive) { coordinator.deleteEntry(entry) }
    }

    private func loadThumbnail() {
        guard let url = coordinator.thumbnailURL(for: entry) else { return }
        thumbnailImage = NSImage(contentsOf: url)
    }
}
