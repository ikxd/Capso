// App/Sources/Preferences/Tabs/GeneralSettingsView.swift
import SwiftUI
import LaunchAtLogin

struct GeneralSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    let updateManager: UpdateManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Startup") {
                SettingCard {
                    SettingRow(label: "Launch at Login", sublabel: "Start Capso when you log in") {
                        LaunchAtLogin.Toggle { Text("") }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    // TODO: Re-enable "Show Menu Bar Icon" once MenuBarController
                    // actually respects AppSettings.showMenuBarIcon. Today it
                    // unconditionally installs the status item in
                    // setupStatusItem(), so this toggle did nothing when flipped.
                    // Uncomment the SettingRow below when the feature is wired.
                    // SettingRow(label: "Show Menu Bar Icon", showDivider: true) {
                    //     Toggle("", isOn: $viewModel.showMenuBarIcon)
                    //         .toggleStyle(.switch)
                    //         .controlSize(.small)
                    // }
                }
            }

            SettingGroup(title: "Feedback") {
                SettingCard {
                    SettingRow(label: "Shutter Sound", sublabel: "Play sound after capture") {
                        Toggle("", isOn: $viewModel.playShutterSound)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            if let updateManager {
                SettingGroup(title: "Updates") {
                    SettingCard {
                        SettingRow(label: "Check for Updates", sublabel: "Automatically checks daily") {
                            CheckForUpdatesView(updateManager: updateManager)
                        }
                    }
                }
            }

            SettingGroup(title: "History") {
                SettingCard {
                    SettingRow(label: "Save to History", sublabel: "Automatically save all captures") {
                        Toggle("", isOn: $viewModel.historyEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Keep History", sublabel: "Auto-delete older captures", showDivider: true) {
                        Picker("", selection: $viewModel.historyRetention) {
                            Text("1 Week").tag("oneWeek")
                            Text("2 Weeks").tag("twoWeeks")
                            Text("1 Month").tag("oneMonth")
                            Text("Unlimited").tag("unlimited")
                        }
                        .frame(width: 130)
                    }
                }
            }

            SettingGroup(title: "About") {
                SettingCard {
                    SettingRow(label: "Version") {
                        Text(viewModel.appVersion)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }
                }
            }
        }
    }


}
