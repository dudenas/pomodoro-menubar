import Foundation
import AppKit
import Combine

@MainActor
final class TimerEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    /// What we write to disk so a running/paused pomodoro survives quit + restart.
    private enum PersistedState: Codable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        // Written by the short-lived build that had breaks. Still decoded so
        // such a file is recognised and dropped instead of misread.
        case breakRunning(endsAt: Date, long: Bool)
        case breakPaused(remaining: TimeInterval, long: Bool)
    }

    static let focusDuration: TimeInterval = 25 * 60

    @Published private(set) var state: State = .idle
    @Published private(set) var remaining: TimeInterval = TimerEngine.focusDuration

    private var ticker: AnyCancellable?
    private let onComplete: (Date) -> Void
    private let logEvent: (Event.Kind, Int?, Date) -> Void
    private let stateURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        onComplete: @escaping (Date) -> Void,
        logEvent: @escaping (Event.Kind, Int?, Date) -> Void
    ) {
        self.onComplete = onComplete
        self.logEvent = logEvent

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
        self.stateURL = dir.appendingPathComponent("timerState.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        restoreFromDisk()
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Time already spent in the current pomodoro (0 when idle).
    var elapsed: TimeInterval {
        state == .idle ? 0 : max(0, Self.focusDuration - remaining)
    }

    func start() {
        let toCountDown: TimeInterval
        let wasPaused: Bool
        switch state {
        case .idle:
            toCountDown = Self.focusDuration
            wasPaused = false
        case .paused(let r):
            toCountDown = r
            wasPaused = true
        case .running:
            return
        }
        let endsAt = Date().addingTimeInterval(toCountDown)
        state = .running(endsAt: endsAt)
        remaining = toCountDown
        startTicker()
        persistState()
        logEvent(wasPaused ? .resumed : .started, nil, Date())
    }

    func pause() {
        guard case .running(let endsAt) = state else { return }
        let r = max(0, endsAt.timeIntervalSinceNow)
        state = .paused(remaining: r)
        remaining = r
        ticker?.cancel()
        ticker = nil
        persistState()
        logEvent(.paused, Int(r), Date())
    }

    func cancel() {
        let r: Int?
        switch state {
        case .running(let endsAt):
            r = Int(max(0, endsAt.timeIntervalSinceNow))
        case .paused(let rem):
            r = Int(rem)
        case .idle:
            return
        }
        state = .idle
        remaining = Self.focusDuration
        ticker?.cancel()
        ticker = nil
        persistState()
        logEvent(.cancelled, r, Date())
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard case .running(let endsAt) = state else { return }
        let r = endsAt.timeIntervalSinceNow
        if r <= 0 {
            finish(at: endsAt)
        } else {
            remaining = r
        }
    }

    private func finish(at completedAt: Date) {
        ticker?.cancel()
        ticker = nil
        state = .idle
        remaining = Self.focusDuration
        persistState()

        // Sound only fires for live completions — not when we discover one
        // happened while the app was closed.
        let isLive = abs(completedAt.timeIntervalSinceNow) < 2
        if isLive {
            SoundPlayer.shared.playCompletion()
        }

        logEvent(.completed, nil, completedAt)
        onComplete(completedAt)
    }

    // MARK: - Persistence

    private func persistState() {
        switch state {
        case .idle:
            try? FileManager.default.removeItem(at: stateURL)
        case .running(let endsAt):
            write(.running(endsAt: endsAt))
        case .paused(let r):
            write(.paused(remaining: r))
        }
    }

    private func write(_ persisted: PersistedState) {
        guard let data = try? encoder.encode(persisted) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func restoreFromDisk() {
        guard let data = try? Data(contentsOf: stateURL),
              let persisted = try? decoder.decode(PersistedState.self, from: data) else {
            return
        }

        switch persisted {
        case .running(let endsAt):
            let now = Date()
            if endsAt > now {
                // Still running — pick up where we were. Not logged: relaunching
                // the app isn't something the user did to the pomodoro.
                state = .running(endsAt: endsAt)
                remaining = endsAt.timeIntervalSince(now)
                startTicker()
            } else {
                // Would have completed while we were away — log a completion
                // at its original end time, then return to idle.
                finish(at: endsAt)
            }
        case .paused(let r):
            state = .paused(remaining: r)
            remaining = r
        case .breakRunning, .breakPaused:
            // Breaks no longer exist; a leftover break just ends.
            try? FileManager.default.removeItem(at: stateURL)
        }
    }
}
