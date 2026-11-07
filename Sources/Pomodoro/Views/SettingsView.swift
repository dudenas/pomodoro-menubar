import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(SoundSettings.enabledKey) private var soundEnabled: Bool = true
    @AppStorage(SoundSettings.soundKey) private var soundID: String = SoundSettings.defaultSoundID
    @AppStorage(SoundSettings.breakSoundKey) private var breakSoundID: String = SoundSettings.defaultBreakSoundID
    @AppStorage(SoundSettings.volumeKey) private var volume: Double = SoundSettings.defaultVolume
    @AppStorage(SoundSettings.customPathKey) private var customPath: String = ""

    @AppStorage(GoalSettings.key) private var dailyGoal: Int = GoalSettings.defaultGoal
    @AppStorage(BreakSettings.shortKey) private var shortBreak: Int = BreakSettings.defaultShort
    @AppStorage(BreakSettings.longKey) private var longBreak: Int = BreakSettings.defaultLong
    @AppStorage(BreakSettings.everyKey) private var longEvery: Int = BreakSettings.defaultEvery
    @AppStorage(BreakSettings.autoStartKey) private var autoStartBreaks: Bool = false

    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Stepper(value: $dailyGoal, in: 0...30) {
                    LabeledContent("Pomodoros a day", value: dailyGoal == 0 ? "Off" : "\(dailyGoal)")
                }
            } header: {
                Text("Daily goal")
            } footer: {
                Text("Shown as a bar under today's count, and marked in History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $shortBreak, in: 1...30) {
                    LabeledContent("Short break", value: "\(shortBreak) min")
                }
                Stepper(value: $longBreak, in: 5...60, step: 5) {
                    LabeledContent("Long break", value: "\(longBreak) min")
                }
                Stepper(value: $longEvery, in: 2...12) {
                    LabeledContent("Long break", value: "every \(longEvery) pomodoros")
                }
                Toggle("Start breaks automatically", isOn: $autoStartBreaks)
            } header: {
                Text("Breaks")
            } footer: {
                Text("Breaks don't count as pomodoros. An unused break suggestion clears after 20 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Play sounds", isOn: $soundEnabled)

                Group {
                    Picker("When a pomodoro ends", selection: $soundID) { soundOptions }
                        .onChange(of: soundID) { _ in preview(soundID) }

                    Picker("When a break ends", selection: $breakSoundID) { soundOptions }
                        .onChange(of: breakSoundID) { _ in preview(breakSoundID) }

                    LabeledContent("Volume") {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: $volume, in: 0.1...1) { editing in
                                if !editing { preview(soundID) }
                            }
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button {
                            preview(soundID)
                        } label: {
                            Label("Preview", systemImage: "play.fill")
                        }
                        Spacer()
                        Button("Use my own file…") { chooseFile() }
                    }
                }
                .disabled(!soundEnabled)
            } header: {
                Text("Sound")
            }

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
        .frame(width: 440, height: 640)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    @ViewBuilder
    private var soundOptions: some View {
        ForEach(SoundLibrary.builtIn) { Text($0.name).tag($0.id) }
        Divider()
        ForEach(SoundLibrary.system) { Text("\($0.name) (macOS)").tag($0.id) }
        if let custom = SoundLibrary.custom(path: customPath) {
            Divider()
            Text("\(custom.name) (file)").tag(custom.id)
        }
    }

    private func preview(_ id: String) {
        SoundPlayer.shared.play(id: id, volume: volume)
    }

    /// The chosen file becomes the pomodoro-end sound (it's also selectable
    /// for breaks from the list).
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Pick a sound to play when a pomodoro ends"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customPath = url.path
        if soundID == SoundLibrary.customID {
            preview(soundID)  // selection didn't change, so onChange won't fire
        } else {
            soundID = SoundLibrary.customID
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
