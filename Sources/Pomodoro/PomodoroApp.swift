import SwiftUI
import AppKit

/// Drives the History window's navigation stack so the menu can reset it to
/// "today" each time History is opened.
@MainActor
final class HistoryNav: ObservableObject {
    @Published var path: [Date] = []
}

@MainActor
final class AppContainer: ObservableObject {
    let store: LogStore
    let engine: TimerEngine
    let eventLog: EventLog
    let historyNav = HistoryNav()

    init() {
        let eventLog = EventLog()
        let store = LogStore()
        self.store = store
        self.eventLog = eventLog
        self.engine = TimerEngine(
            onComplete: { [weak store] completedAt in
                store?.add(source: .timer, at: completedAt)
            },
            logEvent: { [weak eventLog] kind, remaining, at in
                eventLog?.log(kind, remainingSec: remaining, at: at)
            }
        )
        DispatchQueue.main.async { FileSafety.reportIncidents() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon — menu bar app only.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer()

    init() {
        // Before AppContainer exists, so a second copy never loads or saves.
        SingleInstance.exitIfAlreadyRunning()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(container.store)
                .environmentObject(container.engine)
                .environmentObject(container.eventLog)
                .environmentObject(container.historyNav)
        } label: {
            MenuBarLabel()
                .environmentObject(container.engine)
        }
        .menuBarExtraStyle(.window)

        Window("Pomodoro History", id: "history") {
            HistoryView()
                .environmentObject(container.store)
                .environmentObject(container.eventLog)
                .environmentObject(container.historyNav)
        }
        .defaultSize(width: 520, height: 560)

        Window("Pomodoro Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 440, height: 520)
        .windowResizability(.contentSize)
    }
}
