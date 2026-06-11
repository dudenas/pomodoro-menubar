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
            Image(systemName: engine.isRunning ? "timer.circle.fill" : "timer")
            if engine.isRunning {
                Text(formatMMSS(engine.remaining))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject var store: LogStore
    @EnvironmentObject var engine: TimerEngine
    @EnvironmentObject var eventLog: EventLog
    @EnvironmentObject var nav: HistoryNav
    @Environment(\.openWindow) private var openWindow

    @State private var minutesInput: String = ""
    @FocusState private var minutesFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(formatMMSS(engine.remaining))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .padding(.top, 12)

            HStack(spacing: 10) {
                Button(action: primaryTap) {
                    Label(primaryLabel, systemImage: primaryIcon)
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { engine.cancel() }) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(engine.state == .idle)
            }

            // Hidden button: Space toggles Start/Pause, but only when the
            // minutes field is not being edited (so Space can be typed there).
            Button(action: primaryTap) { EmptyView() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(minutesFocused)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            Divider()

            // Pomodoro count row
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

                Spacer()
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(store.todayCount)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if store.todayBonusCycles > 0 {
                            Text("+\(store.todayBonusCycles)")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text("pomodoros today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            }

            // Extra minutes block
            VStack(spacing: 8) {
                HStack {
                    Text("Extra minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Three explicit stats: minutes to next cycle / total today / bonus cycles
                HStack(spacing: 0) {
                    statCell(value: "\(minutesToNext)", caption: "to next")
                    statDivider
                    statCell(value: "\(store.todayMinutes)", caption: "min today",
                             emphasized: store.todayMinutes != 0)
                    statDivider
                    statCell(value: "+\(store.todayBonusCycles)", caption: "cycles",
                             emphasized: store.todayBonusCycles > 0)
                }

                HStack(spacing: 6) {
                    quickMinuteButton(5)
                    quickMinuteButton(10)
                    quickMinuteButton(15)
                    quickMinuteButton(25)
                }

                HStack(spacing: 6) {
                    TextField("min (negative to subtract)", text: $minutesInput)
                        .textFieldStyle(.roundedBorder)
                        .focused($minutesFocused)
                        .frame(maxWidth: .infinity)
                        .onSubmit { commitMinutesInput() }
                    Button("Add") { commitMinutesInput() }
                        .disabled(parsedMinutesInput == nil)
                }
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
    }

    // MARK: - Minutes stat cells

    @ViewBuilder
    private func statCell(value: String, caption: String, emphasized: Bool = true) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.body, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(emphasized ? .primary : .secondary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 26)
    }

    /// Minutes until the extra-minutes pool rolls another bonus cycle.
    private var minutesToNext: Int {
        let total = store.todayMinutes
        guard total > 0 else { return LogStore.minutesPerCycle }
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
    }

    private func addMinutes(_ m: Int) {
        eventLog.log(.minutesAdded, minutes: m)
        store.addMinutes(m)
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
