// App/Sources/Preferences/Components/CheckForUpdatesView.swift
import SwiftUI
import Sparkle

/// A SwiftUI wrapper that observes the Sparkle updater's `canCheckForUpdates`
/// state and exposes a "Check for Updates" button.
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates") {
            checkForUpdatesViewModel.updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
        .controlSize(.small)
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    let updater: SPUUpdater
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        self.updater = updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }
}
