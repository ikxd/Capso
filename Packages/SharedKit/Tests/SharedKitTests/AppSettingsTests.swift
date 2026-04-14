import Foundation
import Testing
@testable import SharedKit

@Suite("AppSettings")
struct AppSettingsTests {
    @Test("Default export location is Desktop")
    func defaultExportLocation() {
        let settings = AppSettings()
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        #expect(settings.exportLocation == desktopURL)
    }

    @Test("Default screenshot format is PNG")
    func defaultScreenshotFormat() {
        let settings = AppSettings()
        #expect(settings.screenshotFormat == .png)
    }

    @Test("Default Quick Access position is bottomLeft")
    func defaultQuickAccessPosition() {
        let settings = AppSettings()
        #expect(settings.quickAccessPosition == .bottomLeft)
    }

    @Test("Default shutter sound is enabled")
    func defaultShutterSound() {
        let settings = AppSettings()
        #expect(settings.playShutterSound == true)
    }

    @Test("Default auto-close interval is 5 seconds")
    func defaultAutoCloseInterval() {
        let settings = AppSettings()
        #expect(settings.quickAccessAutoCloseInterval == 5)
    }

    @Test("Pro features locked by default")
    func proFeaturesLockedByDefault() {
        let settings = AppSettings()
        #expect(settings.isProUnlocked == false)
    }

    @Test("File formats map common extensions")
    func fileFormatExtensionMapping() {
        #expect(FileFormat(pathExtension: "png") == .png)
        #expect(FileFormat(pathExtension: "jpg") == .jpeg)
        #expect(FileFormat(pathExtension: "jpeg") == .jpeg)
        #expect(FileFormat(pathExtension: "gif") == .gif)
        #expect(FileFormat(pathExtension: "mp4") == .mp4)
        #expect(FileFormat(pathExtension: "mov") == .mov)
        #expect(FileFormat(pathExtension: "webm") == nil)
    }

    @Test("Generated file names preserve the requested extension")
    func generatedFileNamesUseFormatExtension() {
        let date = Date(timeIntervalSince1970: 0)

        #expect(
            FileNaming.generateFileName(for: .screenshot, format: .png, date: date).hasSuffix(".png")
        )
        #expect(
            FileNaming.generateFileName(for: .recording, format: .gif, date: date).hasSuffix(".gif")
        )
        #expect(
            FileNaming.generateFileName(for: .recording, format: .mov, date: date).hasSuffix(".mov")
        )
    }
}
