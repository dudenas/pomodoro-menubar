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

    enum Phase: Equatable {
        case focus
        case shortBreak
        case longBreak

        var isBreak: Bool { self != .focus }
    }

    /// What we write to disk so a running/paused timer survives quit + restart.
    /// Breaks get their own cases so files written by older (focus-only)
    /// builds still decode unchanged.
    private enum PersistedState: Codable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case breakRunning(endsAt: Date, long: Bool)
        case breakPaused(remaining: TimeInterval, long: Bool)
    }

    static let focusDuration: TimeInterval = 25 * 60
    /// A suggested break that is never started reverts to "focus" after this.
    static let breakSuggestionTTL: TimeInterval = 20 * 60

    @Published private(set) var state: State = .idle
    /// While running or paused: what is counting down.
    /// While idle: what Start will start (a break is suggested after a pomodoro).
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: TimeInterval = TimerEngine.focusDuration

    private var ticker: AnyCancellable?
    private var suggestionExpiry: Task<Void, Never>?
    /// Wall-clock deadline for a suggested break; checked on wake and on Start
    /// so a night's sleep can't leave a stale "Time for a break".
    private var breakSuggestionExpiresAt: Date?
    private var wakeObserver: NSObjectProtocol?
    private let onComplete: (Date) -> Void
    private let logEvent: (Event.Kind, Int?, Date) -> Void
    /// Timer-completed pomodoros today, including the one just logged.
    private let focusCountToday: () -> Int
    private let stateURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        onComplete: @escaping (Date) -> Void,
        logEvent: @escaping (Event.Kind, Int?, Date) -> Void,
        focusCountToday: @escaping () -> Int
    ) {
        self.onComplete = onComplete
        self.logEvent = logEvent
        self.focusCountToday = focusCountToday

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

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.expireBreakSuggestionIfDue() }
        }
    }

    deinit {
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return Self.focusDuration
        case .shortBreak: return TimeInterval(BreakSettings.shortMinutes * 60)
        case .longBreak: return TimeInterval(BreakSettings.longMinutes * 60)
        }
    }

    /// Time already spent in the current run (0 when idle).
    var elapsed: TimeInterval {
        state == .idle ? 0 : max(0, duration(of: phase) - remaining)
    }

    /// What the big clock should show.
    var displayRemaining: TimeInterval {
        state == .idle ? duration(of: phase) : remaining
    }

    func start() {
        let toCountDown: TimeInterval
        let wasPaused: Bool
        switch state {
        case .idle:
            expireBreakSuggestionIfDue()
            toCountDown = duration(of: phase)
            wasPaused = false
        case .paused(let r):
            toCountDown = r
            wasPaused = true
        case .running:
            return
        }
        clearBreakSuggestion()
        let endsAt = Date().addingTimeInterval(toCountDown)
        state = .running(endsAt: endsAt)
        remaining = toCountDown
        startTicker()
        persistState()
        // Breaks are deliberately not logged (see Event.Kind).
        if phase == .focus {
            logEvent(wasPaused ? .resumed : .started, nil, Date())
        }
    }

    func pause() {
        guard case .running(let endsAt) = state else { return }
        let r = max(0, endsAt.timeIntervalSinceNow)
        state = .paused(remaining: r)
        remaining = r
        ticker?.cancel()
        ticker = nil
        persistState()
        if phase == .focus {
            logEvent(.paused, Int(r), Date())
        }
    }

    /// Focus: throws the pomodoro away. Break: ends it early.
    func cancel() {
        let r: Int
        switch state {
        case .running(let endsAt):
            r = Int(max(0, endsAt.timeIntervalSinceNow))
        case .paused(let rem):
            r = Int(rem)
        case .idle:
            return
        }
        let ended = phase
        state = .idle
        phase = .focus
        remaining = Self.focusDuration
        ticker?.cancel()
        ticker = nil
        persistState()
        if ended == .focus {
            logEvent(.cancelled, r, Date())
        }
    }

    /// Drops a suggested (not yet started) break so Start begins a pomodoro.
    func skipBreak() {
        guard state == .idle, phase.isBreak else { return }
        clearBreakSuggestion()
        phase = .focus
        remaining = Self.focusDuration
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
        let finished = phase

        // Sound (and a break suggestion) only for live completions — not when
        // we discover one that happened while the app was closed or asleep.
        let isLive = abs(completedAt.timeIntervalSinceNow) < 2

        if finished == .focus {
            if isLive { SoundPlayer.shared.play(.focusEnd) }
            logEvent(.completed, nil, completedAt)
            onComplete(completedAt)
            if isLive {
                let n = focusCountToday()
                let every = BreakSettings.longEvery
                phase = (n > 0 && n % every == 0) ? .longBreak : .shortBreak
                suggestBreak()
            } else {
                phase = .focus
            }
        } else {
            if isLive { SoundPlayer.shared.play(.breakEnd) }
            phase = .focus
        }

        remaining = duration(of: phase)
        persistState()

        if finished == .focus, phase.isBreak, BreakSettings.autoStart {
            start()
        }
    }

    private func suggestBreak() {
        let ttl = Self.breakSuggestionTTL
        breakSuggestionExpiresAt = Date().addingTimeInterval(ttl)
        suggestionExpiry?.cancel()
        suggestionExpiry = Task { [weak self] in
            // Continuous clock keeps counting while the Mac sleeps.
            let clock = ContinuousClock()
            try? await Task.sleep(until: clock.now.advanced(by: .seconds(ttl)), clock: clock)
            guard !Task.isCancelled else { return }
            self?.expireBreakSuggestionIfDue()
        }
    }

    /// Drops a suggested break whose time has passed.
    func expireBreakSuggestionIfDue() {
        guard state == .idle, phase.isBreak,
              let expiresAt = breakSuggestionExpiresAt,
              Date() >= expiresAt.addingTimeInterval(-1) else { return }
        skipBreak()
    }

    private func clearBreakSuggestion() {
        suggestionExpiry?.cancel()
        suggestionExpiry = nil
        breakSuggestionExpiresAt = nil
    }

    // MARK: - Persistence

    private func persistState() {
        let long = phase == .longBreak
        switch state {
        case .idle:
            try? FileManager.default.removeItem(at: stateURL)
        case .running(let endsAt):
            write(phase == .focus ? .running(endsAt: endsAt) : .breakRunning(endsAt: endsAt, long: long))
        case .paused(let r):
            write(phase == .focus ? .paused(remaining: r) : .breakPaused(remaining: r, long: long))
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
            resumeOrFinish(endsAt: endsAt, phase: .focus)
        case .breakRunning(let endsAt, let long):
            resumeOrFinish(endsAt: endsAt, phase: long ? .longBreak : .shortBreak)
        case .paused(let r):
            phase = .focus
            state = .paused(remaining: r)
            remaining = r
        case .breakPaused(let r, let long):
            phase = long ? .longBreak : .shortBreak
            state = .paused(remaining: r)
            remaining = r
        }
    }

    private func resumeOrFinish(endsAt: Date, phase restored: Phase) {
        phase = restored
        let now = Date()
        if endsAt > now {
            // Still running — pick up where we were. Not logged: relaunching
            // the app isn't something the user did to the pomodoro.
            state = .running(endsAt: endsAt)
            remaining = endsAt.timeIntervalSince(now)
            startTicker()
        } else {
            // Ended while we were away — log it at its original end time.
            finish(at: endsAt)
        }
    }
}
