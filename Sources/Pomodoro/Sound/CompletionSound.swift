import AppKit

enum SoundSettings {
    static let enabledKey = "soundEnabled"
    static let soundKey = "completionSound"
    static let volumeKey = "soundVolume"
    static let customPathKey = "customSoundPath"

    /// Singing bowl was the user's pick of the first round.
    static let defaultSoundID = SoundLibrary.synthID(.singingBowl)
    /// The synth sounds are normalised near full scale, ~17 dB hotter than
    /// macOS's Glass; 0.4 lands them noticeable but not startling.
    static let defaultVolume = 0.4
}

/// A completion sound the user can pick in Settings.
struct SoundOption: Identifiable, Hashable {
    enum Source: Hashable {
        case synth(SynthPreset)
        case system(String)
        case file(URL)
    }

    let id: String
    let name: String
    let source: Source
}

enum SoundLibrary {
    static let customID = "file"

    static func synthID(_ preset: SynthPreset) -> String { "synth.\(preset.rawValue)" }

    static let builtIn: [SoundOption] = SynthPreset.allCases.map {
        SoundOption(id: synthID($0), name: $0.displayName, source: .synth($0))
    }

    /// Whatever is in /System/Library/Sounds on this Mac (Glass, Ping, Hero…).
    static let system: [SoundOption] = {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
            .map { SoundOption(id: "system.\($0)", name: $0, source: .system($0)) }
    }()

    static func custom(path: String) -> SoundOption? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return SoundOption(id: customID, name: url.deletingPathExtension().lastPathComponent, source: .file(url))
    }

    static func resolve(_ id: String) -> SoundOption {
        if id == customID,
           let c = custom(path: UserDefaults.standard.string(forKey: SoundSettings.customPathKey) ?? "") {
            return c
        }
        return (builtIn + system).first { $0.id == id }
            ?? builtIn.first { $0.id == SoundSettings.defaultSoundID }!
    }
}

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// Held so the sound isn't deallocated mid-play, and so a new preview
    /// can cut off the previous one.
    private var current: NSSound?
    private var synthCache: [SynthPreset: Data] = [:]

    /// Plays the user's chosen sound, if sound is on.
    func playCompletion() {
        let d = UserDefaults.standard
        guard d.object(forKey: SoundSettings.enabledKey) as? Bool ?? true else { return }
        play(
            id: d.string(forKey: SoundSettings.soundKey) ?? SoundSettings.defaultSoundID,
            volume: d.object(forKey: SoundSettings.volumeKey) as? Double ?? SoundSettings.defaultVolume
        )
    }

    func play(id: String, volume: Double) {
        current?.stop()
        // A missing custom file falls back to the default, so a completion is never silent.
        guard let sound = makeSound(SoundLibrary.resolve(id))
                ?? makeSound(SoundLibrary.resolve(SoundSettings.defaultSoundID)) else { return }
        sound.volume = Float(max(0, min(1, volume)))
        current = sound
        sound.play()
    }

    private func makeSound(_ option: SoundOption) -> NSSound? {
        switch option.source {
        case .synth(let preset):
            let data: Data
            if let cached = synthCache[preset] {
                data = cached
            } else {
                data = Synth.wav(Synth.render(preset.spec))
                synthCache[preset] = data
            }
            return NSSound(data: data)
        case .system(let name):
            return NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
        case .file(let url):
            return NSSound(contentsOf: url, byReference: true)
        }
    }
}
