# Decisions log

Product and engineering decisions made while building v1 (2026-10-01 – 2026-10-03), newest last. The spec reflects all of them; this file records the why.

## Product (decided by the user)

- Personal, local build; no Mac App Store sandbox. Keep a Developer ID path open.
- Watch CPU and memory per app (helpers grouped) and per process; network monitoring deferred.
- No macOS notifications. Barking = bark sound + red animated dog; the popover never opens on its own — clicking the barking dog opens it in alert mode.
- Reminder barks at +10 s, +30 s and +90 s while the dog is still barking.
- Actions: Quit by default, ⌥ turns it into Kill; Snooze (15 min / 1 h / until tomorrow), Ignore, Always ignore. You choose app or process.
- Limits via a Chill ↔ Paranoid slider plus Advanced numbers (memory shown in GB). Polling interval configurable: 2 / 5 / 10 / 30 s, default 5 s.
- Popover lists the top N rows (default 5) with "+N more…"; clicking the dog anytime shows the live list. Launch at login and Pause watching are in v1.
- Skins: Symbol dog (SF Symbols dog + mood badge, default), Pixel symbol dog (same art as pixel art), the original Pixel dog, Shiba. Mood badges: napping = outline dog + zzz, sniffing = ?, growling = orange !!, barking = red dog + sound waves, sulking = dog turned away + rain cloud, proud = heart.
- Per-app memory allowance as a "Bowl" submenu in the row's ⋯ menu (Regular / Big / Huge / Bottomless), saved per app; chosen over a Settings slider tab and an "It needs this much" bark button. Memory only. Plain dog words, the GB limits appear while ⌥ is held. Settings' Ignore list tab became Exceptions and lists the bowls.
- Real bark sounds (CC BY-SA 3.0 recording, see README credits).
- `miawMiawCPU`: a CLI stress toy with delays, repeat cycles and ramp/spike patterns.

## Engineering rulings (made during implementation)

- Code inside a `.app` groups under its own outermost `.app`; the responsible-PID lookup is used only for `.xpc`-only paths. Otherwise tools run from Terminal (Python.app, Xcode toolchain) were blamed on Terminal and Quit/Kill hit Terminal.
- An app's main process is the member in `Contents/MacOS/`, preferring the bundle's `CFBundleExecutable` — so Quit asks the real app politely (save prompts) instead of SIGTERMing every helper.
- A snoozed or always-ignored breach re-alerts when the mute ends; "Ignore this time" covers the whole episode.
- Dismissing an alert popover (Esc, click outside, dog click, or opening Settings from it) means "seen it": the dog sulks until the hog calms down. (Open question: should closing count as Ignore instead?)
- Kill sends SIGKILL to every member, main process first; `PosixSignaller` refuses non-positive PIDs.
- Self-cost budget < 1 % of one core while calm: `make install` ships Release; the popover's SwiftUI host exists only while shown; sorting is done once per tick; history trims incrementally; only the current user's processes are sampled; responsible PIDs and paths are cached per process identity. Measured 0.74 % (Release, calm).
- The popover is a non-activating `NSPanel` at `.popUpMenu` level that joins all Spaces and full-screen apps; it is placed under the dog, never above the menu bar, and its list scrolls (expanded list capped at 30 entities).
- Pixel symbol dog frames carry a 1× representation (27×18 grid) and a 2× one (54×36 grid); its portraits use the 54×36 grid at 1-pt cells so badges survive. Smooth skins scale portraits with interpolation, pixel skins without.
- The app icon is the smooth symbol dog on a cream→orange rounded square; the in-app icon follows the selected skin; the Finder icon is never rewritten at runtime (it would break the code signature).
- History was rewritten to the personal identity (micmnm@gmail.com) before the first push; the repo uses `gh` credentials for GitHub.

- Bowls are factors of the shared memory limit (1.5×, 2×, none), not absolute GB, so they follow the sensitivity slider. Picking a bowl the app now fits under mutes the running memory breach immediately (as Ignore); otherwise the breach would linger for 3 calm ticks.

## Explicitly skipped for now (user decision)

- Two entities showing the same memory value (e.g. JetBrains Rider and node at 10.38 GB) — not investigated.
- A report that the popover header didn't refresh — could not be reproduced on a fresh launch; not changed.
