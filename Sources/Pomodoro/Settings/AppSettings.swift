import Foundation
import AppKit

/// UserDefaults keys and defaults for settings read outside SwiftUI views.
enum BreakSettings {
    static let shortKey = "shortBreakMinutes"
    static let longKey = "longBreakMinutes"
    static let everyKey = "longBreakEvery"
    static let autoStartKey = "autoStartBreaks"

    static let defaultShort = 5
    static let defaultLong = 15
    static let defaultEvery = 4

    static var shortMinutes: Int { int(shortKey, defaultShort, 1...60) }
    static var longMinutes: Int { int(longKey, defaultLong, 1...60) }
    static var longEvery: Int { int(everyKey, defaultEvery, 2...12) }
    static var autoStart: Bool { UserDefaults.standard.bool(forKey: autoStartKey) }

    private static func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        let v = UserDefaults.standard.object(forKey: key) as? Int ?? fallback
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

enum GoalSettings {
    static let key = "dailyGoal"
    /// Median day in the log at the time this shipped was 10.
    static let defaultGoal = 10
}

@MainActor
enum FileSafety {
    /// Messages for the user about files set aside during this launch.
    private static var incidents: [String] = []

    /// Moves a data file that exists but can't be decoded out of the way, so
    /// the next save starts a fresh file instead of overwriting the old one.
    /// Returns false if it couldn't be moved — callers must then not save.
    static func quarantine(_ url: URL) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(name).unreadable-\(f.string(from: Date())).\(url.pathExtension)")
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            incidents.append("\(url.lastPathComponent) couldn't be read. It was kept, untouched, as \(dest.lastPathComponent), and a new empty file was started.")
            return true
        } catch {
            incidents.append("\(url.lastPathComponent) couldn't be read or moved aside. To protect it, nothing new will be saved to it until it's fixed or removed — changes made now will be lost on quit.")
            return false
        }
    }

    /// Shows one alert listing anything set aside at launch. Nothing is deleted.
    static func reportIncidents() {
        guard !incidents.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Pomodoro couldn't read part of its history"
        alert.informativeText = incidents.joined(separator: "\n\n")
            + "\n\nFolder: ~/Library/Application Support/Pomodoro/"
        alert.alertStyle = .warning
        incidents = []
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum SingleInstance {
    static let bundleID = "xyz.circa.pomodoro"

    /// Two copies would each save their own in-memory history over the
    /// other's, so a second copy quits before it loads anything.
    static func exitIfAlreadyRunning() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard let other = others.first else { return }
        let msg = "Pomodoro is already running (pid \(other.processIdentifier)); quitting so the two copies don't overwrite each other's history.\n"
        FileHandle.standardError.write(Data(msg.utf8))
        exit(0)
    }
}
