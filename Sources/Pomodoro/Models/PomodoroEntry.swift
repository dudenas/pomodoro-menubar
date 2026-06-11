import Foundation

struct PomodoroEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let completedAt: Date
    let source: Source
    /// Only meaningful when `source == .minutes` — the number of partial-session
    /// minutes logged. Nil for full-pomodoro entries (timer + manual).
    let minutes: Int?

    enum Source: String, Codable {
        case timer     // pomodoro completed via the timer
        case manual    // manually added full pomodoro via "+"
        case minutes   // partial-session minutes added via the "Add minutes" UI
        case rollover  // pomodoro auto-created when 25 extra minutes accumulated
    }

    init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        source: Source,
        minutes: Int? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.source = source
        self.minutes = minutes
    }
}

struct LogFile: Codable {
    var entries: [PomodoroEntry]
}
