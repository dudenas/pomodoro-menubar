import Foundation
import AppKit
import Combine

/// One day's aggregated totals, used by the History list. A real Identifiable
/// struct (not a tuple) so SwiftUI's ForEach diffs rows by stable identity.
struct DayStat: Identifiable, Equatable {
    let date: Date          // startOfDay, local calendar
    let count: Int          // direct pomodoros (timer + manual)
    let minutes: Int        // raw extra minutes (can be negative)
    let bonusCycles: Int    // floor(minutes / 25), >= 0
    let total: Int          // count + bonusCycles
    var id: Date { date }
}

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [PomodoroEntry] = []
    /// Bumped whenever the calendar day changes (midnight crossing, wake-from-sleep
    /// across midnight, timezone change). Triggers a re-render of any view observing
    /// LogStore, so derived values recompute even without an entry mutation.
    @Published private(set) var dayTick: Int = 0

    static let minutesPerCycle = 25

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var dayChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lastSeenDay: Date

    init() {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Pomodoro", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("log.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        self.lastSeenDay = Calendar.current.startOfDay(for: Date())

        load()
        installDayChangeObservers()
    }

    deinit {
        if let o = dayChangeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    // MARK: - Mutations

    func add(source: PomodoroEntry.Source, at date: Date = Date()) {
        entries.append(PomodoroEntry(completedAt: date, source: source))
        save()
    }

    /// Add `minutes` of partial-session time (not a full pomodoro). May be
    /// negative to subtract. Cycle conversion is derived at display time —
    /// nothing is auto-rolled in storage.
    func addMinutes(_ minutes: Int, at date: Date = Date()) {
        guard minutes != 0 else { return }
        entries.append(PomodoroEntry(completedAt: date, source: .minutes, minutes: minutes))
        save()
    }

    /// Remove the most recent pomodoro entry from today (timer or manual,
    /// not minutes entries). No-op if there isn't one.
    func removeMostRecentToday() {
        let cal = Calendar.current
        if let idx = entries.lastIndex(where: {
            cal.isDateInToday($0.completedAt) && ($0.source == .timer || $0.source == .manual)
        }) {
            entries.remove(at: idx)
            save()
        }
    }

    // MARK: - Derived (today)

    /// Direct pomodoro completions today (timer + manual). Excludes derived
    /// bonus cycles from minutes — use `todayTotalCycles` for the combined number.
    var todayCount: Int {
        let cal = Calendar.current
        return entries.reduce(into: 0) { acc, e in
            guard cal.isDateInToday(e.completedAt) else { return }
            if e.source == .timer || e.source == .manual { acc += 1 }
        }
    }

    /// Raw sum of extra-minute entries logged today. Can be negative if the
    /// user subtracted too much.
    var todayMinutes: Int {
        let cal = Calendar.current
        return entries.reduce(into: 0) { acc, e in
            if e.source == .minutes, cal.isDateInToday(e.completedAt) {
                acc += e.minutes ?? 0
            }
        }
    }

    /// Bonus cycles derived from today's extra minutes — `floor(min / 25)`,
    /// clamped at zero.
    var todayBonusCycles: Int {
        bonusCycles(forMinutes: todayMinutes)
    }

    var todayTotalCycles: Int {
        todayCount + todayBonusCycles
    }

    // MARK: - Derived (history)

    /// Returns per-day totals for the last `days` days, newest first.
    /// `count` is direct completions; `bonusCycles` is derived from minutes;
    /// `total = count + bonusCycles`.
    func dailyTotals(days: Int) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var counts: [Date: Int] = [:]
        var minutes: [Date: Int] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.completedAt)
            switch e.source {
            case .minutes:
                minutes[day, default: 0] += e.minutes ?? 0
            case .timer, .manual:
                counts[day, default: 0] += 1
            case .rollover:
                // Legacy entries (pre-migration) — count as a direct pomodoro
                // so totals don't change for users who already had them.
                counts[day, default: 0] += 1
            }
        }
        var result: [DayStat] = []
        for offset in 0..<days {
            if let day = cal.date(byAdding: .day, value: -offset, to: today) {
                let c = counts[day] ?? 0
                let m = minutes[day] ?? 0
                let b = Self.bonusCycles(forMinutes: m)
                result.append(DayStat(date: day, count: c, minutes: m, bonusCycles: b, total: c + b))
            }
        }
        return result
    }

    /// Backwards-compatible: total cycles per day (count + bonus).
    func dailyCounts(days: Int) -> [(date: Date, count: Int)] {
        dailyTotals(days: days).map { ($0.date, $0.total) }
    }

    // MARK: - Cycle math

    static func bonusCycles(forMinutes m: Int) -> Int {
        m <= 0 ? 0 : m / minutesPerCycle
    }

    private func bonusCycles(forMinutes m: Int) -> Int {
        Self.bonusCycles(forMinutes: m)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(LogFile.self, from: data) else {
            entries = []
            return
        }
        let migrated = migrate(file.entries)
        entries = migrated.entries
        if migrated.changed {
            save() // Persist the cleaned form so it's not redone next launch.
        }
    }

    /// One-time silent migration: drop any `.rollover` entries that were
    /// materialized by the short-lived auto-rollover behavior. The underlying
    /// `.minutes` entries remain, and cycles are derived at display time.
    private func migrate(_ raw: [PomodoroEntry]) -> (entries: [PomodoroEntry], changed: Bool) {
        let filtered = raw.filter { $0.source != .rollover }
        return (filtered, filtered.count != raw.count)
    }

    private func save() {
        let file = LogFile(entries: entries)
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func installDayChangeObservers() {
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkDayChange() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkDayChange() }
        }
    }

    private func checkDayChange() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != lastSeenDay {
            lastSeenDay = today
            dayTick &+= 1
        }
    }
}
