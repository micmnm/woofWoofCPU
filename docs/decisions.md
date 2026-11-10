# Decisions log

Product and engineering decisions made while building v1 (2026-10-01 – 2026-10-03) and the strain-aware barking amendment (2026-11-01), newest last. The spec reflects all of them; this file records the why.

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
- A snoozed or always-ignored breach re-alerts when the mute ends, after a fresh full window. Ignore ("Ignore for now") mutes the app and resource until it has had no breach for 10 min (see the strain section below).
- Dismissing an alert popover (Esc, click outside, dog click, or opening Settings from it) means "seen it": the dog sulks until the hog calms down. (Open question: should closing count as Ignore instead?)
- Kill sends SIGKILL to every member, main process first; `PosixSignaller` refuses non-positive PIDs.
- Self-cost budget < 1 % of one core while calm: `make install` ships Release; the popover's SwiftUI host exists only while shown; sorting is done once per tick; history trims incrementally; only the current user's processes are sampled; responsible PIDs and paths are cached per process identity. Measured 0.74 % (Release, calm).
- The popover is a non-activating `NSPanel` at `.popUpMenu` level that joins all Spaces and full-screen apps; it is placed under the dog, never above the menu bar, and its list scrolls (expanded list capped at 30 entities).
- Pixel symbol dog frames carry a 1× representation (27×18 grid) and a 2× one (54×36 grid); its portraits use the 54×36 grid at 1-pt cells so badges survive. Smooth skins scale portraits with interpolation, pixel skins without.
- The app icon is the Pixel pup's Proud sprite in cream on a teal rounded square (tail dropped at 16 px); the in-app icon follows the selected skin; the Finder icon is never rewritten at runtime (it would break the code signature).

- Bowls are factors of the shared memory limit (1.5×, 2×, none), not absolute GB, so they follow the sensitivity slider. Picking a bowl the app now fits under mutes the running memory breach immediately (as Ignore); otherwise the breach would linger through the 60 s calm period.

## Strain-aware barking (2026-11-01)

Why: a fixed limit means different things on different Macs. On an 8 GB fanless Air a browser sits over the old 1.6 GB limit most of the day and the dog barked at it constantly, while on a 64 GB desktop the same limits never fired even when the Mac was swapping. Ignore was also undone by a short dip, and a busy browser or video call looked like a runaway.

### User decisions

- The dog barks when the Mac is strained on a resource **and** an app is the cause; limits follow RAM, cores, memory pressure, heat and battery.
- **Runaway:** any one process at ≥ 90% CPU, with no upper cap (a multi-core export, encode, VM or game counts too), barks after the runaway window on a calm Mac too. What's usual for the app does not hold it back; the user silences deliberate jobs with Ignore or Always ignore.

### Calls made in the design (to tune after a week of real use)

- The sensitivity numbers in spec §4.4 are a starting point.
- 60 s calm period before a breach ends; 10 min Ignore cooldown; 3-day half-life and 2 h of learning for usual usage.
- Strained with nobody to blame: a header line only, no bark and no mood change.
- Usual usage lives in a JSON file in Application Support, not `UserDefaults`, because it is larger and written more often.
- Memory pressure is polled with `sysctl` each tick rather than a `DispatchSource`, so it fits the tick model and is easy to fake.
- Custom limits keep the other fields of the stop they were edited from; old stored custom values get the rest from Balanced.
- Progress counts time over: the clock stops while calm, and an alert fires only on a tick where the pair is over.
- Ignore survives sleep/wake and pause but not a relaunch.
- Strain and runaway each keep their own over-time; the breach shows whichever is further along.

### Rulings made while building it

- Usual usage uses a plain time-weighted mean while the history is shorter than the half-life window, then the 3-day EWMA (`alpha = max(decay, elapsed / observed)`). With a pure EWMA the value "learned after 2 h" would be close to the first sample.
- The mood engine prunes expired Ignores before refreshing the keys that are present; otherwise an Ignore for a constantly present key would never expire.
- `Limits(cpu:memory:)` stays as a convenience init that fills the strain fields from Balanced's values, which keeps call sites unchanged.
- Strain windows are the stop's CPU and memory windows. Runaway is CPU-only. On battery or in Low Power Mode the runaway window is halved and the busy trigger is 25 points lower (never below 0).
- Usual suppression applies to the strain path only, and only strictly above the usual high. While a breach continues, the floor, CPU minimum, share and runaway threshold are × 0.9.
- A Bottomless bowl is never a memory culprit.
- Per-reason clocks add the time since the last tick, except on a reason's first tick; absent reasons are frozen. Progress is the maximum over reasons, ties go to strain, and a restart (snooze end) zeroes every reason.
- The strain line says "running hot" only when CPU is strained and thermal ≥ serious; the battery and Low Power Mode variants need CPU strain too. Memory comes first.
- Advanced labels read "CPU: app uses more than (% of one core)", "for", "Memory: app holds more than" and "for", which merges the new meaning with the voice guide's unit clarity.
- The napping line is seeded by the hours since the reference date; seeding by the literal hour of day made the rare line unreachable.
- Settings says "Patrol" for the check interval and "Breed" for the skin; the skins are Classic, 8-bit classic, Pixel pup and Shiba.
- On an 8 GB Mac memory pressure sits at warning most of the day, so Balanced waits for critical; pick Alert to react at warning.

## Explicitly skipped for now (user decision)

- Two entities showing the same memory value (e.g. JetBrains Rider and node at 10.38 GB) — not investigated.
- A report that the popover header didn't refresh — could not be reproduced on a fresh launch; not changed.
