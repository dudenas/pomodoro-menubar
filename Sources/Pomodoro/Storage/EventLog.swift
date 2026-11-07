import Foundation
import Combine

@MainActor
final class EventLog: ObservableObject {
    @Published private(set) var events: [Event] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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
        self.fileURL = dir.appendingPathComponent("events.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    func log(
        _ kind: Event.Kind,
        remainingSec: Int? = nil,
        minutes: Int? = nil,
        at date: Date = Date()
    ) {
        events.append(Event(
            timestamp: date,
            kind: kind,
            remainingSec: remainingSec,
            minutes: minutes
        ))
        save()
    }

    /// Events that occurred on the given calendar day, oldest first.
    func events(on day: Date) -> [Event] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events
            .filter { $0.timestamp >= start && $0.timestamp < end }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Set when an unreadable events file couldn't be moved aside; saving
    /// would overwrite it, so we don't.
    private var saveBlocked = false

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            events = []
            return
        }
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(EventFile.self, from: data) else {
            saveBlocked = !FileSafety.quarantine(fileURL)
            events = []
            return
        }
        events = file.events
    }

    private func save() {
        guard !saveBlocked else { return }
        let file = EventFile(events: events)
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
