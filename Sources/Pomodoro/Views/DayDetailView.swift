import SwiftUI

struct DayDetailView: View {
    let day: Date
    @EnvironmentObject var eventLog: EventLog
    @EnvironmentObject var store: LogStore

    var body: some View {
        let events = eventLog.events(on: day)
        let (pomodoros, extraMinutes) = totals(on: day)
        let bonusCycles = LogStore.bonusCycles(forMinutes: extraMinutes)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summaryText(pomodoros: pomodoros, bonus: bonusCycles, minutes: extraMinutes))
                        .foregroundStyle(.secondary)
                    Text("\(events.count) events")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No activity recorded for this day.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(events) { event in
                            EventRow(event: event)
                        }
                    }
                    .padding(.trailing, 14)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 520)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: day)
    }

    private func totals(on day: Date) -> (pomodoros: Int, minutes: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return (0, 0) }
        var pomodoros = 0
        var minutes = 0
        for entry in store.entries where entry.completedAt >= start && entry.completedAt < end {
            switch entry.source {
            case .minutes:
                minutes += entry.minutes ?? 0
            case .timer, .manual, .rollover:
                // .rollover is legacy; treat as a direct pomodoro for old data.
                pomodoros += 1
            }
        }
        return (pomodoros, minutes)
    }

    private func summaryText(pomodoros: Int, bonus: Int, minutes: Int) -> String {
        var parts: [String] = []
        if bonus > 0 {
            parts.append("\(pomodoros) + \(bonus) cycles")
        } else {
            parts.append("\(pomodoros) pomodoros")
        }
        if minutes != 0 {
            parts.append("\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }
}

private struct EventRow: View {
    let event: Event

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Image(systemName: event.kind.systemImage)
                .frame(width: 18)
                .foregroundStyle(color)

            Text(event.kind.label)
                .foregroundStyle(.primary)

            if let r = event.remainingSec {
                Text("(\(mmss(r)) left)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let m = event.minutes {
                Text(m > 0 ? "+\(m) min" : "\(m) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private var color: Color {
        switch event.kind {
        case .completed:          return .green
        case .started, .resumed:  return .accentColor
        case .paused:             return .orange
        case .cancelled:          return .red
        case .manualAdded:        return .accentColor
        case .manualRemoved:      return .secondary
        case .minutesAdded:       return .teal
        case .pomodoroRolledOver: return .purple
        }
    }

    private func mmss(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}
