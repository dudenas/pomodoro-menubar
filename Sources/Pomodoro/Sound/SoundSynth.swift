import Foundation

/// Completion sounds rendered in code (additive synthesis), so the app needs no
/// bundled audio files. Each preset is a few struck notes, each made of sine
/// partials with their own exponential decay — higher partials die faster,
/// which is what makes a struck bell or bar sound natural instead of beepy.
enum SynthPreset: String, CaseIterable {
    case softChime
    case warmBell
    case singingBowl
    case marimba

    var displayName: String {
        switch self {
        case .softChime: return "Soft chime"
        case .warmBell: return "Warm bell"
        case .singingBowl: return "Singing bowl"
        case .marimba: return "Marimba"
        }
    }

    var spec: SynthSpec {
        switch self {
        case .softChime:
            // Rising G-major arpeggio, glassy but soft-edged.
            return SynthSpec(
                notes: [
                    .init(freq: 783.99, at: 0.00, gain: 0.80),   // G5
                    .init(freq: 987.77, at: 0.17, gain: 0.80),   // B5
                    .init(freq: 1174.66, at: 0.34, gain: 0.90),  // D6
                ],
                partials: [
                    .init(ratio: 1.0, amp: 1.00, decay: 1.30),
                    .init(ratio: 2.0, amp: 0.22, decay: 0.55),
                    .init(ratio: 3.0, amp: 0.07, decay: 0.30),
                    .init(ratio: 4.2, amp: 0.035, decay: 0.12),
                ],
                attack: 0.004,
                length: 3.6
            )
        case .warmBell:
            // One strike of a round bell; slight beating on the low partials
            // gives it the slow shimmer of a real bell.
            return SynthSpec(
                notes: [.init(freq: 523.25, at: 0, gain: 1)],  // C5
                partials: [
                    .init(ratio: 0.5, amp: 0.30, decay: 3.50),
                    .init(ratio: 1.0, amp: 1.00, decay: 3.00, beat: 0.7),
                    .init(ratio: 2.0, amp: 0.55, decay: 2.00, beat: 1.1),
                    .init(ratio: 3.0, amp: 0.25, decay: 1.20),
                    .init(ratio: 4.2, amp: 0.15, decay: 0.60),
                    .init(ratio: 5.4, amp: 0.08, decay: 0.35),
                    .init(ratio: 6.8, amp: 0.04, decay: 0.20),
                ],
                attack: 0.003,
                length: 5.0
            )
        case .singingBowl:
            // Long, low, wavering ring. Inharmonic bowl partials, each beating.
            return SynthSpec(
                notes: [.init(freq: 392.0, at: 0, gain: 1)],  // G4
                partials: [
                    .init(ratio: 1.00, amp: 1.00, decay: 3.50, beat: 1.3),
                    .init(ratio: 2.71, amp: 0.50, decay: 2.40, beat: 2.2),
                    .init(ratio: 5.15, amp: 0.18, decay: 1.20, beat: 3.1),
                    .init(ratio: 8.00, amp: 0.06, decay: 0.50),
                ],
                attack: 0.010,
                length: 6.5
            )
        case .marimba:
            // Quick wooden C-major run, dry and friendly.
            return SynthSpec(
                notes: [
                    .init(freq: 523.25, at: 0.00, gain: 0.80),   // C5
                    .init(freq: 659.25, at: 0.12, gain: 0.80),   // E5
                    .init(freq: 783.99, at: 0.24, gain: 0.85),   // G5
                    .init(freq: 1046.50, at: 0.36, gain: 1.00),  // C6
                ],
                partials: [
                    .init(ratio: 1.0, amp: 1.00, decay: 0.45),
                    .init(ratio: 4.0, amp: 0.28, decay: 0.09),
                    .init(ratio: 9.9, amp: 0.06, decay: 0.035),
                ],
                attack: 0.002,
                length: 1.8
            )
        }
    }
}

struct SynthSpec {
    struct Note {
        let freq: Double
        let at: Double     // seconds from start
        let gain: Double
    }

    struct Partial {
        let ratio: Double  // multiple of the note's frequency
        let amp: Double
        let decay: Double  // time constant, seconds
        var beat: Double = 0  // Hz; >0 adds a detuned twin for a slow wobble
    }

    let notes: [Note]
    let partials: [Partial]
    let attack: Double
    let length: Double
}

enum Synth {
    static let sampleRate = 44_100.0

    static func render(_ spec: SynthSpec) -> [Float] {
        let n = Int(spec.length * sampleRate)
        var buf = [Double](repeating: 0, count: n)
        let nyquistSafe = sampleRate * 0.45

        for note in spec.notes {
            let start = Int(note.at * sampleRate)
            guard start < n else { continue }
            for p in spec.partials {
                let f = note.freq * p.ratio
                guard f < nyquistSafe else { continue }
                let w = 2 * Double.pi * f / sampleRate
                let wb = 2 * Double.pi * (f + p.beat) / sampleRate
                let k = 1.0 / (p.decay * sampleRate)
                let amp = note.gain * p.amp
                for i in 0..<(n - start) {
                    let decayEnv = exp(-Double(i) * k)
                    if decayEnv < 1e-5 { break }
                    let t = Double(i) / sampleRate
                    var env = decayEnv
                    if t < spec.attack {
                        // Raised-cosine onset: avoids the click of a hard start.
                        env *= 0.5 - 0.5 * cos(Double.pi * t / spec.attack)
                    }
                    var s = sin(w * Double(i))
                    if p.beat != 0 {
                        s = 0.5 * (s + sin(wb * Double(i)))
                    }
                    buf[start + i] += amp * env * s
                }
            }
        }

        // Fade the tail so the sound never ends on a cut.
        let fade = min(Int(0.3 * sampleRate), n)
        for i in 0..<fade {
            let x = Double(i) / Double(fade)
            buf[n - 1 - i] *= x * x
        }

        // Normalise to just under full scale.
        let peak = buf.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? 0.89 / peak : 0
        return buf.map { Float($0 * gain) }
    }

    /// 16-bit mono PCM WAV, ready for `NSSound(data:)`.
    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func ascii(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        let rate = UInt32(sampleRate)
        let dataBytes = UInt32(samples.count * 2)
        ascii("RIFF"); u32(36 + dataBytes); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        ascii("data"); u32(dataBytes)
        d.reserveCapacity(d.count + samples.count * 2)
        for s in samples {
            let v = Int16((max(-1, min(1, s)) * 32767).rounded())
            u16(UInt16(bitPattern: v))
        }
        return d
    }
}
