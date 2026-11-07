import SwiftUI

/// One calendar week of day rows, newest day first.
private struct WeekGroup: Identifiable {
    let start: Date
    let days: [DayStat]
    var id: Date { start }
    var total: Int { days.reduce(0) { $0 + $1.total } }
}

struct HistoryView: View {
    @EnvironmentObject var store: LogStore
    @EnvironmentObject var eventLog: EventLog
    @EnvironmentObject var nav: HistoryNav
    @AppStorage(GoalSettings.key) private var dailyGoal: Int = GoalSettings.defaultGoal

    /// This week plus the four before it.
    private let weeksShown = 5

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstDay = cal.date(byAdding: .weekOfYear, value: -(weeksShown - 1), to: thisWeek) ?? today
        let dayCount = (cal.dateComponents([.day], from: firstDay, to: today).day ?? 34) + 1
        let stats = store.dailyTotals(days: dayCount)
        let weeks = Self.group(stats, cal: cal)
        let maxTotal = max(1, stats.map(\.total).max() ?? 1, dailyGoal)
        let sumPomodoros = stats.reduce(0) { $0 + $1.count }
        let sumBonus = stats.reduce(0) { $0 + $1.bonusCycles }
        let sumMinutes = stats.reduce(0) { $0 + $1.minutes }
        let sumTotal = sumPomodoros + sumBonus

        NavigationStack(path: $nav.path) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History")
                        .font(.title2.bold())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sumTotal == 1 ? "1 pomodoro" : "\(sumTotal) pomodoros")
                            .font(.headline)
                            .monospacedDigit()
                        if sumBonus > 0 {
                            Text("\(sumPomodoros) + \(sumBonus) from \(sumMinutes) extra min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text("last \(weeksShown) weeks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Click a day to see its timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(weeks) { week in
                            WeekHeader(week: week, title: Self.weekTitle(week.start, thisWeek: thisWeek, cal: cal),
                                       goal: dailyGoal)
                            ForEach(week.days) { stat in
                                NavigationLink(value: stat.date) {
                                    HistoryRow(stat: stat, maxTotal: maxTotal, goal: dailyGoal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.trailing, 14)
                }
            }
            .padding(20)
            .frame(minWidth: 500, minHeight: 520)
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
                    .environmentObject(eventLog)
                    .environmentObject(store)
            }
        }
    }

    private static func group(_ stats: [DayStat], cal: Calendar) -> [WeekGroup] {
        var groups: [WeekGroup] = []
        for stat in stats {
            let start = cal.dateInterval(of: .weekOfYear, for: stat.date)?.start ?? stat.date
            if let last = groups.last, last.start == start {
                groups[groups.count - 1] = WeekGroup(start: start, days: last.days + [stat])
            } else {
                groups.append(WeekGroup(start: start, days: [stat]))
            }
        }
        return groups
    }

    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMM d"
        return f
    }()

    private static func weekTitle(_ start: Date, thisWeek: Date, cal: Calendar) -> String {
        if start == thisWeek { return "This week" }
        if let last = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek), start == last {
            return "Last week"
        }
        return "Week of \(weekFormatter.string(from: start))"
    }
}

private struct WeekHeader: View {
    let week: WeekGroup
    let title: String
    let goal: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            // Today only counts once it's met — it isn't a miss while in progress.
            let judged = week.days.filter { !Calendar.current.isDateInToday($0.date) || $0.total >= goal }
            if goal > 0, !judged.isEmpty {
                Text("goal met \(judged.filter { $0.total >= goal }.count) of \(judged.count) \(judged.count == 1 ? "day" : "days")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("\(week.total)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }
}

private struct HistoryRow: View {
    let stat: DayStat
    let maxTotal: Int
    let goal: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(stat.label)
                .frame(width: 110, alignment: .leading)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(isEmpty ? .secondary : .primary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(metGoal ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * ratio(stat.total))
                    if goal > 0 {
                        // Goal marker
                        Rectangle()
                            .fill(Color.primary.opacity(0.35))
                            .frame(width: 1.5)
                            .offset(x: geo.size.width * ratio(goal) - 0.75)
                    }
                }
            }
            .frame(height: 14)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    if metGoal {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .accessibilityLabel("Goal met")
                    }
                    Text("\(stat.total)")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isEmpty ? .secondary : .primary)
                }
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 90, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.001)) // hit-test only
        )
    }

    private var isEmpty: Bool { stat.total == 0 && stat.minutes == 0 }
    private var metGoal: Bool { goal > 0 && stat.total >= goal }

    /// The split behind the total, only when there is one to show.
    private var detail: String? {
        if stat.bonusCycles > 0 { return "\(stat.count) + \(stat.bonusCycles) · \(stat.minutes)m" }
        if stat.minutes != 0 { return "\(stat.minutes)m extra" }
        return nil
    }

    private func ratio(_ value: Int) -> CGFloat {
        guard maxTotal > 0 else { return 0 }
        return min(1, CGFloat(value) / CGFloat(maxTotal))
    }
}
