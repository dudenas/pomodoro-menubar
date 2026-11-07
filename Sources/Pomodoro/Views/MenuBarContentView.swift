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
        guard engine.isRunning else { return "timer" }
        return engine.phase.isBreak ? "cup.and.saucer.fill" : "timer.circle.fill"
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject var store: LogStore
    @EnvironmentObject var engine: TimerEngine
    @EnvironmentObject var eventLog: EventLog
    @EnvironmentObject var nav: HistoryNav
    @Environment(\.openWindow) private var openWindow
    @AppStorage(GoalSettings.key) private var dailyGoal: Int = GoalSettings.defaultGoal
    // Observed only so the idle clock redraws when break lengths change.
    @AppStorage(BreakSettings.shortKey) private var shortBreak: Int = BreakSettings.defaultShort
    @AppStorage(BreakSettings.longKey) private var longBreak: Int = BreakSettings.defaultLong

    @State private var minutesInput: String = ""
    @FocusState private var minutesFocused: Bool
    /// First Cancel tap on a pomodoro older than a minute only arms it.
    @State private var cancelArmed = false
    @State private var disarmTask: Task<Void, Never>?

    /// Below this, Cancel acts at once — nothing worth protecting yet.
    private static let cancelConfirmAfter: TimeInterval = 60

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(phaseCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(engine.phase.isBreak ? Color.mint : Color.secondary)
                Text(formatMMSS(engine.displayRemaining))
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
            .padding(.top, 8)

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

            if let undo = store.undoLabel {
                Button(action: undoLast) {
                    Label("Undo \(undo)", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

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

    @ViewBuilder
    private var controls: some View {
        if engine.state == .idle && engine.phase.isBreak {
            HStack(spacing: 10) {
                Button(action: { engine.start() }) {
                    Label("Start break", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip break") { engine.skipBreak() }
                    .controlSize(.large)
                    .help("Go straight back to focus")
            }
        } else {
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
                        Text(engine.phase.isBreak ? "End break" : "Cancel")
                    }
                }
                .controlSize(.large)
                .disabled(engine.state == .idle)
                .help(engine.phase.isBreak ? "End the break now" : "Throw this pomodoro away")
            }
        }
    }

    private var phaseCaption: String {
        switch (engine.state, engine.phase) {
        case (.idle, .shortBreak): return "Time for a break"
        case (.idle, .longBreak): return "Time for a long break"
        case (_, .shortBreak): return "Break"
        case (_, .longBreak): return "Long break"
        case (_, .focus): return "Focus"
        }
    }

    private func cancelTap() {
        if engine.phase.isBreak || engine.elapsed < Self.cancelConfirmAfter || cancelArmed {
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
            Button {
                if store.todayCount > 0 {
                    eventLog.log(.manualRemoved)
                    store.removeMostRecentToday()
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .disabled(store.todayCount == 0)
            .help("Remove the last pomodoro")

            Spacer()
            VStack(spacing: 2) {
                // The total is the headline; the split is only detail.
                Text("\(store.todayTotalCycles)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(store.todayTotalCycles == 1 ? "pomodoro today" : "pomodoros today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.todayBonusCycles > 0 {
                    Text("\(store.todayCount) + \(store.todayBonusCycles) from extra minutes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
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
            HStack(alignment: .firstTextBaseline) {
                Text("Extra minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.todayMinutes) today · \(minutesToNext) to next pomodoro")
                    .font(.caption)
                    .foregroundStyle(store.todayMinutes != 0 ? .primary : .secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                quickMinuteButton(5)
                quickMinuteButton(10)
                quickMinuteButton(15)
                quickMinuteButton(25)
            }

            HStack(spacing: 6) {
                TextField("Other, e.g. 20 or -10", text: $minutesInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($minutesFocused)
                    .frame(maxWidth: .infinity)
                    .onSubmit { commitMinutesInput() }
                Button("Add") { commitMinutesInput() }
                    .disabled(parsedMinutesInput == nil)
            }
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
        addMinutes(n)
        minutesInput = ""
        minutesFocused = false
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
