import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: LogStore
    @EnvironmentObject var eventLog: EventLog
    @EnvironmentObject var nav: HistoryNav

    private let daysShown = 30

    var body: some View {
        let stats = store.dailyTotals(days: daysShown)
        let maxTotal = max(1, stats.map(\.total).max() ?? 1)
        let sumPomodoros = stats.reduce(0) { $0 + $1.count }
        let sumBonus = stats.reduce(0) { $0 + $1.bonusCycles }
        let sumMinutes = stats.reduce(0) { $0 + $1.minutes }

        NavigationStack(path: $nav.path) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History")
                        .font(.title2.bold())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(sumPomodoros) + \(sumBonus) cycles · \(sumMinutes) min")
                            .foregroundStyle(.secondary)
                        Text("last \(daysShown) days")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Click a day to see its timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(stats) { stat in
                            NavigationLink(value: stat.date) {
                                HistoryRow(stat: stat, maxTotal: maxTotal)
                            }
                            .buttonStyle(.plain)
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
}

private struct HistoryRow: View {
    let stat: DayStat
    let maxTotal: Int

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
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * fillRatio)
                }
            }
            .frame(height: 14)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(stat.count)")
                        .font(.system(.body, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isEmpty ? .secondary : .primary)
                    if stat.bonusCycles > 0 {
                        Text("+\(stat.bonusCycles)")
                            .font(.system(.caption, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if stat.minutes != 0 {
                    Text("\(stat.minutes)m")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 58, alignment: .trailing)

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

    private var fillRatio: CGFloat {
        guard maxTotal > 0 else { return 0 }
        return CGFloat(stat.total) / CGFloat(maxTotal)
    }
}
