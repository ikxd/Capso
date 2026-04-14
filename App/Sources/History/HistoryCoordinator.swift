// App/Sources/History/HistoryCoordinator.swift
import AppKit
import AVFoundation
import Observation
import SharedKit
import CaptureKit
import HistoryKit

@MainActor
@Observable
final class HistoryCoordinator {
    let settings: AppSettings
    private let store: HistoryStore?
    private(set) var entries: [HistoryEntry] = []
    private(set) var totalSize: Int64 = 0
    var currentFilter: HistoryFilter = .all

    private var historyWindow: HistoryWindow?

    init(settings: AppSettings) {
        self.settings = settings
        self.store = try? HistoryStore()
    }

    // MARK: - Window

    func showWindow() {
        if let historyWindow {
            historyWindow.show()
            return
        }
        let window = HistoryWindow(coordinator: self)
        self.historyWindow = window
        window.show()
    }

    // MARK: - Data Loading

    func loadEntries() {
        guard let store else { return }
        do {
            entries = try store.fetchAll(filter: currentFilter)
            totalSize = try store.totalFileSize()
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    func setFilter(_ filter: HistoryFilter) {
        currentFilter = filter
        loadEntries()
    }

    // MARK: - Save Capture to History

    func saveCapture(result: CaptureResult) {
        guard settings.historyEnabled, let store else { return }

        let entryID = UUID()
        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        let fm = FileManager.default

        Task.detached(priority: .utility) {
            do {
                try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)

                // Save full image
                let fullImageName = "capture.png"
                let fullImageURL = entryDir.appendingPathComponent(fullImageName)
                let rep = NSBitmapImageRep(cgImage: result.image)
                guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
                try pngData.write(to: fullImageURL)

                // Generate and save thumbnail
                let thumbName = "thumbnail.jpg"
                let thumbURL = entryDir.appendingPathComponent(thumbName)
                if let thumbData = ThumbnailGenerator.generateThumbnail(from: result.image) {
                    try thumbData.write(to: thumbURL)
                }

                let mode: HistoryCaptureMode = switch result.mode {
                case .area: .area
                case .fullscreen: .fullscreen
                case .window: .window
                case .scrolling: .area
                }

                let appName = result.appName
                    ?? NSWorkspace.shared.frontmostApplication?.localizedName

                let entry = HistoryEntry(
                    id: entryID,
                    captureMode: mode,
                    imageWidth: result.image.width,
                    imageHeight: result.image.height,
                    sourceAppName: appName,
                    sourceAppBundleID: result.appBundleIdentifier
                        ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    sourceWindowTitle: result.windowName,
                    thumbnailFileName: thumbName,
                    fullImageFileName: fullImageName,
                    fileSize: Int64(pngData.count)
                )

                try store.insert(entry)

                await MainActor.run {
                    self.loadEntries()
                }
            } catch {
                print("Failed to save capture to history: \(error)")
            }
        }
    }

    // MARK: - Save Recording to History

    func saveRecording(url: URL, mode: HistoryCaptureMode) {
        guard settings.historyEnabled, let store else { return }

        let entryID = UUID()
        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        let fm = FileManager.default

        Task.detached(priority: .utility) {
            do {
                try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)

                let fileName = url.lastPathComponent
                let destURL = entryDir.appendingPathComponent(fileName)
                try fm.copyItem(at: url, to: destURL)

                let fileSize = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0

                let thumbName = "thumbnail.jpg"
                let thumbURL = entryDir.appendingPathComponent(thumbName)
                if let thumbImage = await Self.extractFirstFrame(from: destURL),
                   let thumbData = ThumbnailGenerator.generateThumbnail(from: thumbImage) {
                    try thumbData.write(to: thumbURL)
                }

                let entry = HistoryEntry(
                    id: entryID,
                    captureMode: mode,
                    imageWidth: 0,
                    imageHeight: 0,
                    sourceAppName: NSWorkspace.shared.frontmostApplication?.localizedName,
                    sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    thumbnailFileName: thumbName,
                    fullImageFileName: fileName,
                    fileSize: fileSize
                )

                try store.insert(entry)
                await MainActor.run { self.loadEntries() }
            } catch {
                // Silently fail
            }
        }
    }

    private static func extractFirstFrame(from videoURL: URL) async -> CGImage? {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        do {
            let (image, _) = try await generator.image(at: .zero)
            return image
        } catch {
            return nil
        }
    }

    // MARK: - Actions

    func deleteEntry(_ entry: HistoryEntry) {
        guard let store else { return }
        do {
            try store.delete(id: entry.id)
            let entryDir = store.entriesDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: entryDir)
            loadEntries()
        } catch {
            print("Failed to delete history entry: \(error)")
        }
    }

    func clearAll() {
        guard let store else { return }
        do {
            try HistoryCleanup.clearAll(store: store)
            loadEntries()
        } catch {
            print("Failed to clear history: \(error)")
        }
    }

    func fullImageURL(for entry: HistoryEntry) -> URL? {
        guard let store else { return nil }
        let url = store.entriesDirectory
            .appendingPathComponent(entry.id.uuidString, isDirectory: true)
            .appendingPathComponent(entry.fullImageFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnailURL(for entry: HistoryEntry) -> URL? {
        guard let store else { return nil }
        let url = store.entriesDirectory
            .appendingPathComponent(entry.id.uuidString, isDirectory: true)
            .appendingPathComponent(entry.thumbnailFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func loadFullImage(for entry: HistoryEntry) -> CGImage? {
        guard let url = fullImageURL(for: entry),
              let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  pngDataProviderSource: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }
        return image
    }

    func copyToClipboard(_ entry: HistoryEntry) {
        guard let image = loadFullImage(for: entry) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.writeObjects([nsImage])
    }

    func saveToFile(_ entry: HistoryEntry) {
        guard let sourceURL = fullImageURL(for: entry) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Capso Screenshot.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let destURL = panel.url {
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
    }

    func showInFinder(_ entry: HistoryEntry) {
        guard let url = fullImageURL(for: entry) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func runCleanup() {
        guard let store else { return }
        let retention = HistoryRetention(rawValue: settings.historyRetention) ?? .oneMonth
        do {
            let removed = try HistoryCleanup.enforce(store: store, retention: retention)
            if removed > 0 {
                print("History cleanup: removed \(removed) expired entries")
                loadEntries()
            }
        } catch {
            print("History cleanup failed: \(error)")
        }
    }

    func entryCount(for filter: HistoryFilter) -> Int {
        guard let store else { return 0 }
        return (try? store.count(filter: filter)) ?? 0
    }
}
