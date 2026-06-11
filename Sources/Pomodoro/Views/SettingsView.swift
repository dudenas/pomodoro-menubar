import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
                if let err = launchError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Pomodoro must be in /Applications for this to work reliably.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Play sound when a pomodoro completes", isOn: $soundEnabled)
            } header: {
                Text("Notifications")
            }

            Section {
                LabeledContent("Storage") {
                    Text("~/Library/Application Support/Pomodoro/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Focus duration") {
                    Text("25 minutes")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            // Revert toggle to actual system state.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
