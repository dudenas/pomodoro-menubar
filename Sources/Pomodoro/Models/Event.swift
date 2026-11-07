import Foundation

struct Event: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    /// Seconds remaining when the event happened — only meaningful for `.paused` and `.cancelled`.
    let remainingSec: Int?
    /// Minutes logged — only meaningful for `.minutesAdded`.
    let minutes: Int?

    enum Kind: String, Codable, CaseIterable {
        case started
        case paused
        case resumed
        case cancelled
        case completed
        case manualAdded
        case manualRemoved
        case minutesAdded
        case pomodoroRolledOver
        // Never add a case here without a migration plan: an older build that
        // meets an unknown kind fails to decode events.json, starts empty and
        // overwrites the whole history on its next save.
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        remainingSec: Int? = nil,
        minutes: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.remainingSec = remainingSec
        self.minutes = minutes
    }
}

struct EventFile: Codable {
    var events: [Event]
}

extension Event.Kind {
    var label: String {
        switch self {
        case .started:             return "Started"
        case .paused:              return "Paused"
        case .resumed:             return "Resumed"
        case .cancelled:           return "Cancelled"
        case .completed:           return "Completed"
        case .manualAdded:         return "Added manually"
        case .manualRemoved:       return "Removed manually"
        case .minutesAdded:        return "Added extra minutes"
        case .pomodoroRolledOver:  return "Rolled over to a pomodoro"
        }
    }

    var systemImage: String {
        switch self {
        case .started:             return "play.fill"
        case .paused:              return "pause.fill"
        case .resumed:             return "play.fill"
        case .cancelled:           return "xmark.circle"
        case .completed:           return "checkmark.circle.fill"
        case .manualAdded:         return "plus.circle"
        case .manualRemoved:       return "minus.circle"
        case .minutesAdded:        return "clock.badge.checkmark"
        case .pomodoroRolledOver:  return "arrow.triangle.2.circlepath"
        }
    }
}
