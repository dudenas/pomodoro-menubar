# Pomodoro (macOS menu bar)

A minimal native macOS menu bar Pomodoro app. 25-minute focus timer, today's total (timer + manual + pomodoros earned from extra minutes) with a daily goal, Undo for manual changes, and a week-by-week history. Data lives in `~/Library/Application Support/Pomodoro/log.json`.

Requirements:
- macOS 13 or newer
- Xcode 15 or newer (or the matching Command Line Tools)

## First-time setup

If you've never accepted the Xcode license on this machine you'll get a license error on first build. Accept it once:

```sh
sudo xcodebuild -license accept
```

## Build & run

From this directory:

```sh
swift run Pomodoro
```

The first run creates `~/Library/Application Support/Pomodoro/log.json`. There is no Dock icon — look for the timer icon in the menu bar at the top of the screen.

## Open in Xcode

```sh
open Package.swift
```

Then Cmd-R to run.

## What's where

- `Sources/Pomodoro/PomodoroApp.swift` — `@main`, sets `.accessory` activation policy, wires the `MenuBarExtra` and `History` window scenes.
- `Sources/Pomodoro/Models/PomodoroEntry.swift` — log entry record (`timer` vs `manual`).
- `Sources/Pomodoro/Storage/LogStore.swift` — JSON read/write, `todayCount`, `dailyCounts(days:)`.
- `Sources/Pomodoro/Timer/TimerEngine.swift` — `idle | running | paused` state machine, ticks every 0.25s, plays the chosen completion sound.
- `Sources/Pomodoro/Settings/AppSettings.swift` — daily-goal setting key, and `FileSafety`: an unreadable `log.json` or `events.json` is moved aside (`*.unreadable-<timestamp>.json`) instead of being overwritten.
- `Sources/Pomodoro/Sound/SoundSynth.swift` — the built-in sounds (Soft chime, Warm bell, Singing bowl, Marimba), synthesised in code; no audio files bundled.
- `Sources/Pomodoro/Sound/CompletionSound.swift` — sound list (built-in + macOS system sounds + your own file), volume, playback.
- `Sources/Pomodoro/Views/SettingsView.swift` — Settings: launch at login, sound on/off, sound picker with preview, volume, "Use my own file…".
- `Sources/Pomodoro/Views/MenuBarContentView.swift` — popover UI (timer, Start/Pause, Cancel, today's count with ± buttons, History, Quit).
- `Sources/Pomodoro/Views/HistoryView.swift` — last 5 weeks grouped by week, bars with a daily-goal marker.

## Quick-test the completion flow

To test the completion path without waiting 25 minutes, temporarily lower the constant in `TimerEngine.swift`:

```swift
static let focusDuration: TimeInterval = 10  // seconds, for testing
```

Then `swift run Pomodoro` → click Start → wait 10s → you should hear the completion sound (Soft chime by default) and see today's count increment. Restore to `25 * 60` before real use.
