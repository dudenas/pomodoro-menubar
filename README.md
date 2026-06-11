# Pomodoro (macOS menu bar)

A minimal native macOS menu bar Pomodoro app. 25-minute focus timer, daily count with manual ± adjustment, and a 30-day history view. Data lives in `~/Library/Application Support/Pomodoro/log.json`.

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
- `Sources/Pomodoro/Timer/TimerEngine.swift` — `idle | running | paused` state machine, ticks every 0.25s, plays the system `Glass` sound on completion.
- `Sources/Pomodoro/Views/MenuBarContentView.swift` — popover UI (timer, Start/Pause, Cancel, today's count with ± buttons, History, Quit).
- `Sources/Pomodoro/Views/HistoryView.swift` — last 30 days with horizontal bar chart.

## Quick-test the completion flow

To test the completion path without waiting 25 minutes, temporarily lower the constant in `TimerEngine.swift`:

```swift
static let focusDuration: TimeInterval = 10  // seconds, for testing
```

Then `swift run Pomodoro` → click Start → wait 10s → you should hear the Glass chime and see today's count increment. Restore to `25 * 60` before real use.
