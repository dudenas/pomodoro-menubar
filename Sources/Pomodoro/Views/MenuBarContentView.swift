import SwiftUI
import AppKit

func formatMMSS(_ interval: TimeInterval) -> String {
    let total = max(0, Int(ceil(interval)))
    let m = total / 60
    let s = total % 60
    return String(format: "%02d:%02d", m, s)
}

struct MenuBarLabel: View {
    @EnvironmentObject var engine: TimerEngine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if engine.isRunning {
                Text(formatMMSS(engine.remaining))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
    }

    private var icon: String {
        engine.isRunning ? "timer.circle.fill" : "timer"
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject var store: LogStore
    @EnvironmentObject var engine: TimerEngine
    @EnvironmentObject var eventLog: EventLog
    @EnvironmentObject var nav: HistoryNav
    @Environment(\.openWindow) private var openWindow
    @AppStorage(GoalSettings.key) private var dailyGoal: Int = GoalSettings.defaultGoal

    @State private var minutesInput: String = ""
    @FocusState private var minutesFocused: Bool
    /// First Cancel tap on a pomodoro older than a minute only arms it.
    @State private var cancelArmed = false
    @State private var disarmTask: Task<Void, Never>?
    /// A large custom entry waiting for a second press of Add.
    @State private var pendingLargeMinutes: Int?

    /// Below this, Cancel acts at once — nothing worth protecting yet.
    private static let cancelConfirmAfter: TimeInterval = 60

    var body: some View {
        VStack(spacing: 14) {
            Text(formatMMSS(engine.remaining))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .padding(.top, 12)

            controls

            // Hidden button: Space toggles Start/Pause everywhere, including
            // while the minutes field has focus — it only takes numbers, so a
            // space is never wanted there (and the panel may focus it on open).
            Button(action: primaryTap) { EmptyView() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            Divider()

            countRow

            if dailyGoal > 0 {
                goalBar
            }

            extraMinutes

            // Always present so the popover never changes height; greyed
            // out when there's nothing to undo.
            Button(action: undoLast) {
                Label(store.undoLabel.map { "Undo \($0)" } ?? "Undo",
                      systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(store.undoLabel == nil)

            Divider()

            HStack(spacing: 14) {
                Button {
                    openHistory()
                } label: {
                    Label("History", systemImage: "calendar")
                }
                .buttonStyle(.borderless)

                Button {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.borderless)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 300)
        .onChange(of: engine.state) { _ in disarmCancel() }
    }

    // MARK: - Timer controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: primaryTap) {
                Label(primaryLabel, systemImage: primaryIcon)
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Deliberately narrower than the main button, and a pomodoro
            // more than a minute in needs a second tap to throw away.
            Button(action: cancelTap) {
                if cancelArmed {
                    Text("Discard \(Int(engine.elapsed / 60)) min?")
                        .foregroundStyle(.red)
                } else {
                    Text("Cancel")
                }
            }
            .controlSize(.large)
            .disabled(engine.state == .idle)
            .help("Throw this pomodoro away")
        }
    }

    private func cancelTap() {
        if engine.elapsed < Self.cancelConfirmAfter || cancelArmed {
            disarmCancel()
            engine.cancel()
            return
        }
        cancelArmed = true
        disarmTask?.cancel()
        disarmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { cancelArmed = false }
        }
    }

    private func disarmCancel() {
        disarmTask?.cancel()
        disarmTask = nil
        cancelArmed = false
    }

    // MARK: - Today's count

    private var countRow: some View {
        HStack {
            Button(action: minusTap) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .disabled(store.todayTotalCycles == 0)
            .help(store.todayCount > 0
                  ? "Remove the last pomodoro"
                  : "Subtract \(LogStore.minutesPerCycle) extra minutes (one pomodoro)")

            Spacer()
            VStack(spacing: 2) {
                // The total is the headline; the split is only detail.
                Text("\(store.todayTotalCycles)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(store.todayTotalCycles == 1 ? "pomodoro today" : "pomodoros today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Line always takes its space, so the popover doesn't jump
                // when the first extra-minutes pomodoro appears.
                Text("\(store.todayCount) + \(store.todayBonusCycles) from extra minutes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .opacity(store.todayBonusCycles > 0 ? 1 : 0)
                    .accessibilityHidden(store.todayBonusCycles == 0)
            }
            Spacer()

            Button {
                eventLog.log(.manualAdded)
                store.add(source: .manual)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .help("Add a pomodoro")
        }
    }

    private var goalBar: some View {
        let total = store.todayTotalCycles
        let reached = total >= dailyGoal
        return VStack(spacing: 4) {
            ProgressView(value: Double(min(total, dailyGoal)), total: Double(dailyGoal))
                .tint(reached ? .green : .accentColor)
            Text(reached ? "Daily goal of \(dailyGoal) reached" : "\(dailyGoal - total) to your daily goal of \(dailyGoal)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Extra minutes

    private var extraMinutes: some View {
        VStack(spacing: 8) {
            // Left: extra minutes logged today. Right: what's left until
            // they add up to the next full pomodoro.
            HStack(alignment: .top) {
                minuteStat(value: store.todayMinutes, caption: "extra minutes today",
                           alignment: .leading, dimmed: store.todayMinutes == 0)
                Spacer()
                minuteStat(value: minutesToNext, caption: "left to a full pomodoro",
                           alignment: .trailing, dimmed: false)
            }

            HStack(spacing: 6) {
                quickMinuteButton(5)
                quickMinuteButton(10)
                quickMinuteButton(15)
                quickMinuteButton(25)
            }

            HStack(spacing: 6) {
                Text("Other")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. 20 or -10", text: $minutesInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($minutesFocused)
                    .frame(maxWidth: .infinity)
                    .onSubmit { commitMinutesInput() }
                    .onChange(of: minutesInput) { new in
                        // Numbers only (one leading minus); typing clears a pending confirm.
                        let cleaned = Self.sanitizeMinutes(new)
                        if cleaned != new { minutesInput = cleaned }
                        pendingLargeMinutes = nil
                    }
                Button(action: commitMinutesInput) {
                    // Colour only in the confirm state, so the disabled
                    // look of plain "Add" stays intact.
                    if let pending = pendingLargeMinutes {
                        Text("Add \(pending) min?").foregroundStyle(.orange)
                    } else {
                        Text("Add")
                    }
                }
                .disabled(parsedMinutesInput == nil)
                .help(pendingLargeMinutes != nil
                      ? "That's a lot of minutes — press again to confirm"
                      : "Add these minutes to today")
            }
        }
    }

    private func minuteStat(value: Int, caption: String,
                            alignment: HorizontalAlignment, dimmed: Bool) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text("\(value) min")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Minutes until the extra-minutes pool makes another pomodoro.
    private var minutesToNext: Int {
        let total = store.todayMinutes
        guard total > 0 else { return LogStore.minutesPerCycle - total }
        let r = total % LogStore.minutesPerCycle
        return r == 0 ? LogStore.minutesPerCycle : LogStore.minutesPerCycle - r
    }

    @ViewBuilder
    private func quickMinuteButton(_ m: Int) -> some View {
        Button {
            addMinutes(m)
        } label: {
            Text("+\(m)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var parsedMinutesInput: Int? {
        let trimmed = minutesInput.trimmingCharacters(in: .whitespaces)
        guard let n = Int(trimmed), n != 0 else { return nil }
        return n
    }

    private func commitMinutesInput() {
        guard let n = parsedMinutesInput else { return }
        // Entries above the largest ever logged (120) need a second press,
        // so a typo like 250 for 25 can't silently add 10 pomodoros.
        if abs(n) > Self.confirmMinutesAbove && pendingLargeMinutes != n {
            pendingLargeMinutes = n
            return
        }
        addMinutes(n)
        minutesInput = ""
        pendingLargeMinutes = nil
        minutesFocused = false
    }

    private static let confirmMinutesAbove = 120

    static func sanitizeMinutes(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if ch.isASCII && ch.isNumber { out.append(ch) }
            else if ch == "-" && i == 0 { out.append(ch) }
        }
        return String(out.prefix(5))
    }

    /// Removes the last pomodoro; when today's total comes only from extra
    /// minutes, subtracts one pomodoro's worth of minutes instead.
    private func minusTap() {
        if store.todayCount > 0 {
            eventLog.log(.manualRemoved)
            store.removeMostRecentToday()
        } else if store.todayBonusCycles > 0 {
            addMinutes(-LogStore.minutesPerCycle)
        }
    }

    private func addMinutes(_ m: Int) {
        eventLog.log(.minutesAdded, minutes: m)
        store.addMinutes(m)
    }

    /// Reverts the last +, − or minutes entry, and records the reversal in
    /// the day's timeline with the existing event kinds.
    private func undoLast() {
        guard let undone = store.undoLast() else { return }
        switch undone {
        case .added(let e):
            if e.source == .minutes {
                eventLog.log(.minutesAdded, minutes: -(e.minutes ?? 0))
            } else {
                eventLog.log(.manualRemoved)
            }
        case .removed:
            eventLog.log(.manualAdded)
        }
    }

    private func openHistory() {
        // Always land on today's timeline; Back returns to the archive list.
        nav.path = [Calendar.current.startOfDay(for: Date())]
        openWindow(id: "history")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var primaryLabel: String {
        switch engine.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var primaryIcon: String {
        switch engine.state {
        case .idle, .paused: return "play.fill"
        case .running: return "pause.fill"
        }
    }

    private func primaryTap() {
        switch engine.state {
        case .running: engine.pause()
        case .idle, .paused: engine.start()
        }
    }
}
