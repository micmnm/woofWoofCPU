# Bark when the Mac is hurting — design

Status: Merged into the main spec · Date: 2026-11-01 · Amended §4.4, §4.5, §5.2, §5.3, §6 and §8 of `2026-10-01-woofwoofcpu-design.md`, which stays the authority. Where this document and the code differ, the main spec follows the code.

## 1. Why

The dog is there to protect the user from apps that behave badly **and hurt the Mac**. Today it barks when an app crosses a fixed number (e.g. 20% of RAM for 5 min, or 100% CPU for 3 min). That number means very different things on different Macs:

- On the user's MacBook Air M1 (8 GB, 4P+4E cores, fanless, often on battery) a browser sits at ~1.3–2 GB summed over ~20 helper processes, so the 1.6 GB "Balanced" limit is crossed most of the day and the dog barks at the browser over and over.
- On a 64 GB plugged-in desktop the same limits almost never fire, even when the Mac is genuinely swapping.

Three mechanics make it worse (measured in code, see §3.1): a breach ends after only 3 calm ticks (6–90 s), so Ignore (which covers one breach episode) gets undone by a short dip; a breach that stays over during a snooze barks the instant the snooze ends; and app CPU is the sum of all helpers, so a busy browser or a video call looks like a runaway.

## 2. Goals, non-goals, anti-goals

**Goals**

1. The dog barks only when **(a) the Mac is strained** on a resource **and (b) a specific app is the cause**, sustained for the window. One exception: a single process stuck on a core for a long time (a "runaway") barks even on a calm Mac.
2. Limits follow the hardware automatically: RAM size, core count, memory pressure, heat, battery.
3. The dog learns what is **usual for each app** and does not blame an app for behaving as it usually does.
4. Ignore and Snooze actually make the dog leave an app alone.
5. The popover tells the user when the Mac is strained, even when no single app is to blame.

**Non-goals**

- Watching root/other-user processes (still v1 scope, main spec §4.1).
- Network, disk or GPU strain.
- Showing learned usage as charts or history.
- Notifications outside the menu bar dog.

**Anti-goals** (a failure even if it technically works)

- A busy browser on a calm Mac makes the dog bark.
- The **strain** path barks at the user's own usual heavy work (an Xcode build) every time they do it. Long single-process jobs are the exception: they bark on the runaway path by the user's decision (§3.5).
- Self-cost rises above the main spec's budget (< 1% of one core while calm).
- Use of any new private API (we already have one; don't add more). `sysctl` names and Mach host calls below are public headers.

## 3. Behaviour

### 3.1 Calm period, sticky Ignore, snooze end (fixes that stand alone)

- **Calm period by time.** A breach ends after the entity has been continuously calm for **60 s** (`BreachTracker.calmPeriod`), not after 3 ticks. With 2 s ticks the old rule ended breaches after a 6 s dip.
- **The clock stops while calm.** Progress counts **time spent over**, not time since the breach started: calm ticks inside the calm period don't advance it. An alert fires only on a tick where the entity is over. `Breach` therefore carries the accumulated over-time, plus an `isOver` flag for the current tick.
- **Sticky Ignore.** Ignore mutes the **(entity, resource) pair**, not just the current episode. The mute lasts until that pair has had **no breach for 10 min** (`MoodEngine.ignoreCooldown = 600`). A new episode starting inside the cooldown is still ignored and extends it.
- **Ignore survives sleep/wake and pause** (the user's Air sleeps often). The pair mutes live outside the timer reset: wake and pause clear breach timers, but not mutes. The cooldown counts monotonic uptime, which doesn't advance asleep. Mutes are not saved across relaunch; Always ignore covers permanent cases.
- **Snooze / always-ignore end.** When an entity goes from muted to unmuted (snooze expired, removed from always-ignore, snooze cancelled), every breach of that entity **restarts its window** at that moment (`since = now`). It barks only after a fresh full window, never instantly.
- Pause, sleep/wake and clock jumps keep resetting all timers, as today.

### 3.2 Machine state ("is the Mac hurting?")

Read once per tick, cheaply, with public APIs:

| Field | Source | Notes |
|---|---|---|
| `memoryPressure` normal / warning / critical | `sysctl kern.memorystatus_vm_pressure_level` (1 / 2 / 4) | Polled per tick; any other value → normal. |
| `thermal` nominal / fair / serious / critical | `ProcessInfo.processInfo.thermalState` | |
| `onBattery` | IOKit `IOPSCopyPowerSourcesInfo` / `IOPSGetProvidingPowerSourceType` | Desktop Macs → false. |
| `lowPowerMode` | `ProcessInfo.processInfo.isLowPowerModeEnabled` | |
| `cpuBusy` 0…1 | `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas: (user+system+nice) / all | Whole machine, includes processes the dog can't read. First tick after reset → 0. |
| `logicalCores`, `physicalMemory` | `ProcessInfo` | Constant. |

The Mac is **strained on memory** when pressure ≥ the stop's memory trigger.

The Mac is **strained on CPU** when thermal ≥ the stop's thermal trigger, **or** `cpuBusy` ≥ the stop's busy trigger. On battery or in Low Power Mode, the busy trigger is **25 points lower**.

### 3.3 Culprit ("which app is causing it?")

While the Mac is strained on a resource, an entity is a **culprit** for that resource when all of these hold:

- **Memory:** its footprint ≥ the stop's memory floor × its bowl factor (share of physical RAM). Bottomless bowl → never a memory culprit.
- **CPU:** its CPU ≥ the stop's CPU minimum (% of one core) **and** it holds ≥ the stop's share of the load, where load = `cpuBusy × logicalCores × 100`. If load is 0, the share test passes.
- **Above its usual (§3.4):** if the entity's usual high for that resource is learned, its value must be above it. Not learned yet → this test passes.

While continuing an existing breach, the floor, minimum and share are lowered by 10% (the old hysteresis band). Strain flicker is covered by the 60 s calm period.

### 3.4 What's usual for each app

Per (entity key, resource), keep a time-weighted running **mean and variance** of the value, updated each tick from the elapsed time since the last tick. Use exponential decay with a **half-life of 3 days of observed running time**.

- **Usual high** = mean + 2 × standard deviation, but at least mean × 1.25.
- It counts as **learned** after **2 h** of observed running time. Before that, `usualHigh` is nil.
- Not recorded while paused, for a tick whose elapsed time is > 3× the poll interval (clock jump, sleep), or for the dog itself.
- Entries not seen for **30 days** are pruned. Persisted to `~/Library/Application Support/woofWoofCPU/usual.json` (Codable), written at most every 5 min and on quit. A corrupt or missing file means starting empty; never crash.
- Settings → Exceptions gets a **"Forget what's usual"** button (clears all, with a confirmation).

The effect: the browser's usual 2 GB or Xcode's usual build burst stop counting as misbehaviour. A browser climbing from its usual 2 GB to 5 GB while memory is tight still gets blamed.

### 3.5 Runaway

Independently of strain and usual usage, an entity is **over (CPU, runaway)** when **any one member process** is at ≥ 90% CPU (≈ one full core). It barks after the stop's runaway window, which is **halved on battery or in Low Power Mode**.

- The runaway is judged per process, so one stuck browser tab is caught while normal multi-tab browsing is not.
- **User's decision:** any process at ≥ 90%, with no upper cap (a multi-core export, encode, VM or game counts too), barks after the runaway window. What's usual for the app does **not** hold it back. The user silences deliberate jobs with Ignore or Always ignore.
- It uses the same (entity, CPU) breach key as strain, but **each reason keeps its own over-time**, measured from when that reason first applied. The breach's progress is the higher of the two reasons' progress (each against its own window), and its `reason` is the one with that higher progress. This avoids jumps when a reason appears or drops out mid-breach.
- When the reason is runaway, the popover row's drill-down opens with the stuck process first.

### 3.6 Sensitivity stops (replaces the main spec's §4.4 table)

| Stop | Memory strained at | Memory floor (× RAM) | CPU strained at: thermal ≥ / busy ≥ (on battery) | CPU culprit: min / share of load | Windows CPU / memory | Runaway window |
|---|---|---|---|---|---|---|
| Chill | critical | 25% | critical / 90% (65%) | 200% / 50% | 10 / 15 min | 30 min |
| Relaxed | critical | 20% | serious / 85% (60%) | 150% / 40% | 5 / 10 min | 20 min |
| **Balanced** | critical | 15% | serious / 75% (50%) | 100% / 33% | 3 / 5 min | 10 min |
| Alert | warning | 10% | serious / 60% (35%) | 70% / 25% | 2 / 3 min | 5 min |
| Paranoid | warning | 5% | fair / 50% (25%) | 50% / 20% | 1 / 2 min | 3 min |

Worked example (user's Air, Balanced): memory pressure goes to critical, and the browser holds 2.4 GB (≥ 15% of 8 GB = 1.2 GB) with nothing learned yet. After 5 min the dog barks. Once 2.4 GB has become usual, the dog only barks if the browser grows beyond its usual high.

**Advanced** still shows four editable numbers for the current stop: CPU minimum, CPU window, memory floor and memory window. Editing switches to Custom. Custom keeps the strain triggers, share of load and runaway window of the stop it was edited from, because `Limits` itself carries every field and editing copies the current stop's `Limits`. Old stored custom values that lack the new fields decode them from Balanced.

### 3.7 Popover and copy

- **Strain line:** when the Mac is strained on any resource, the popover header shows one plain line under the funny line, in every mode:
  - "Your Mac is short on memory."
  - "Your Mac is running hot."
  - "Your Mac is working hard on battery." / "Your Mac is working hard in Low Power Mode." / "Your Mac is working hard."
  - If several apply, use the first in that order.
- **No culprit:** strained but nobody to blame (all apps within their usual, or the load is in processes the dog can't see). The dog stays napping/sniffing; nothing barks. The funny line becomes, e.g., "Nobody's misbehaving. {app} just eats the most." above the strain line (list mode only). Exact copy lives in `docs/voice.md`.
- **Runaway copy** joins the bank, e.g. "{app} has a process stuck chewing one core." and "One of {app}'s helpers won't stop spinning."
- **Sparkline limit line:** the dashed line shows the entity's current culprit threshold (floor × bowl, or the CPU minimum). It is omitted when the Mac isn't strained on that resource, and for a runaway breach (the history holds the app's summed CPU).

### 3.8 Mood

The main spec's §4.5 is unchanged except that breaches now come from §3.3–3.5. A breach is still (entity, resource), with progress = elapsed / window.

## 4. Constraints

- Swift 6, strict concurrency, zero warnings, macOS 14, no third-party dependencies (CLAUDE.md).
- All decision logic lives in **WoofCore**, is pure, and is fed by protocols (`MachineStateSource`, existing `ProcessSource`). Live readers live in WoofCore `Sampling/` next to `LibprocProcessSource`, with no AppKit.
- TDD for WoofCore: a failing test first, using fakes (`FakeSource` style).
- Build and test only via the Makefile (`make test`, `make build`). Never `cd` in shell commands.
- Commits: one line, no body, no trailers, no model names.

## 5. Interfaces (contract between work packages)

Names are binding so parallel work fits together. Bodies and private helpers are the builder's call.

```swift
// Sampling/MachineState.swift (WP2)
public enum MemoryPressure: Int, Codable, Comparable, Sendable { case normal, warning, critical }
public enum ThermalLevel: Int, Codable, Comparable, Sendable { case nominal, fair, serious, critical }
public struct MachineState: Equatable, Sendable {
    public var memoryPressure: MemoryPressure
    public var thermal: ThermalLevel
    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var cpuBusy: Double          // 0...1 of all cores
    public var logicalCores: Int
    public var physicalMemory: UInt64
    public static func calm(cores: Int = 8, memory: UInt64 = 8 << 30) -> MachineState
}
public protocol MachineStateSource: Sendable { func read() -> MachineState; func reset() }
public struct HostCPUCalculator: Sendable {          // pure: cumulative host ticks → busy fraction
    public mutating func busy(busyTicks: UInt64, totalTicks: UInt64) -> Double
    public mutating func reset()
}

// Rules/UsualUsage.swift (WP3)
public struct UsualUsage: Codable, Equatable, Sendable {
    public static let halfLife: TimeInterval = 3 * 86_400
    public static let learnedAfter: TimeInterval = 2 * 3_600
    public mutating func record(_ entities: [Entity], elapsed: TimeInterval, maxElapsed: TimeInterval, at date: Date)
    public func usualHigh(_ key: EntityKey, _ resource: Resource) -> Double?   // nil until learned
    public mutating func prune(notSeenSince: Date)
    public mutating func forgetAll()
}

// Rules/Judge.swift (WP4)
public enum BreachReason: String, Codable, Sendable { case strain, runaway }
public struct Verdict: Equatable, Sendable { public let reason: BreachReason; public let window: TimeInterval }
public struct Strain: Equatable, Sendable { public let memory: Bool; public let cpu: Bool }
public enum Judge {
    public static func strain(_ machine: MachineState, _ limits: Limits) -> Strain
    public static func verdicts(_ entity: Entity, _ resource: Resource, machine: MachineState,
                               strain: Strain, limits: Limits, bowl: Bowl,
                               usual: UsualUsage, continuing: Bool) -> [Verdict]   // 0, 1 or 2 (strain, runaway)
}
```

- `Limits` (WP4) grows the fields the stops need: the strain triggers, CPU share, runaway window. Decoding fills missing fields from Balanced. `Sensitivity.limits` fills them from §3.6.
- `BreachTracker.update` (WP1 changes calm; WP4 changes the predicate) takes a closure `(Entity, Resource, _ continuing: Bool) -> [Verdict]` instead of comparing to a threshold. `Breach` gains `reason` and `isOver`, and its progress comes from per-reason over-time (§3.1, §3.5). WP1 introduces over-time and `isOver` for the single existing reason; WP4 adds the second reason.
- Pair mutes for Ignore (WP1) live in a value that `WatchPipeline.resetTimers()` and pause leave untouched.
- `WatchPipeline.step` (WP4) gains `machine: MachineState` and `usual: UsualUsage`, and returns `strain` in `Step`.
- `Sampler.sample` (WP2) returns `Snapshot { entities: [Entity]; machine: MachineState }`. `reset()` also resets the host CPU calculator.

## 6. Work packages (for subagents)

Each package is one subagent, one branch-sized commit or a few, and `make test` green at the end. Packages run in dependency order. **WP1, WP2 and WP3 touch disjoint files and run in parallel.**

| WP | Depends on | Owns (files) | Done when |
|---|---|---|---|
| **WP1 Calm, Ignore, snooze** | — | `Rules/BreachTracker.swift`, `Mood/MoodEngine.swift`, `Pipeline/WatchPipeline.swift`, their tests | §3.1 behaviours are each covered by a test (60 s calm at 2 s and 30 s ticks, Ignore surviving a dip and expiring after 10 min, snooze end restarting the window). Existing tests are updated, not deleted. |
| **WP2 Machine state** | — | new `Sampling/MachineState.swift`, `Sampling/LiveMachineStateSource.swift`, `Sampling/Sampler.swift`, tests, `FakeMachineSource` | `HostCPUCalculator` is tested (first tick 0, deltas, counter wrap → 0). `LiveMachineStateSource` reads all fields. A smoke test asserts sane ranges on this Mac (cores > 0, busy in 0…1). |
| **WP3 Usual usage** | — | new `Rules/UsualUsage.swift`, persistence helper (`Settings/UsualUsageStore.swift`, file I/O), tests | Tests cover decay, the learned threshold, the usual-high floor (≥ 1.25 × mean), skipping big gaps, prune, Codable round-trip, and a corrupt file giving an empty result. |
| **WP4 Judge and stops** | WP1, WP2, WP3 | new `Rules/Judge.swift`, `Rules/Limits.swift`, `BreachTracker` predicate swap, `WatchPipeline` signature, old custom-limits decoding, tests | Each §3.6 stop's numbers are tested. Strain and culprit are tested per resource, including bowl, share of load, usual suppression, continuing −10%, runaway per process, battery halving, per-reason over-time, and the §3.6 worked example as a test. Old custom limits still decode. |
| **WP5 App wiring and UI** | WP4 | `WoofWoofCPU/App/AppCoordinator.swift`, `Popover/*`, `Settings/SettingsView.swift`, `Lines.swift` | Machine state is sampled per tick; usual usage is recorded, saved every 5 min and on quit; the strain line, no-culprit header, runaway copy, sparkline line and "Forget what's usual" all work. `make build` has zero warnings, and screenshots of the header in strained and calm states are attached to the report. |
| **WP6 Docs and manual checks** | WP5 | main spec, `docs/decisions.md`, `docs/manual-checks.md`, README | The main spec's §4.4/§4.5/§5.2/§5.3/§6/§8/§10 reflect this design, and the decisions log records the calls in §8. The manual checks include the §7 scenarios. |

Guidance for every subagent: read CLAUDE.md, the main spec and this doc first. Stay inside your files. If an interface in §5 is wrong, stop and report rather than changing it unilaterally.

**Branch and build.** All work goes on branch `mac-strain`, merged to `main` only after WP6. `make test` and `make build` must pass after every package. WP2 and WP4 may therefore make the **smallest compile-only change** to `AppCoordinator.swift` to keep it building, such as passing `MachineState` through or using `.entities`, with no behaviour change. WP5 replaces those changes properly.

## 7. Verification

Unit tests per package (above). Manual scenarios on the user's Air, Balanced, using `bin/miawMiawCPU` (`make miaw`):

1. **Calm Mac, busy browser:** normal browsing plus a video for 15 min → no bark.
2. **Runaway:** `miawMiawCPU cpu --cores 1 --for 15m` → the dog barks after about 10 min, or about 5 min on battery, with runaway copy.
3. **CPU strain:** `miawMiawCPU cpu --cores all --for 6m` → busy above 75% → barks at miaw after 3 min.
4. **Memory strain (on Alert):** `miawMiawCPU mem --gb 5 --for 10m` → pressure reaches warning → barks at miaw after 3 min. The header shows "short on memory".
5. **Ignore sticks:** Ignore during scenario 4, let memory dip briefly → no new bark within 10 min.
6. **Snooze end:** snooze 15 min with the hog still running → no instant bark when the snooze ends; it barks one window later.
7. **Self-cost** is still below 1% of one core while calm (Activity Monitor, 5 min).

## 8. Calls made in this design (check these)

These are my calls, not the user's decisions:

- The numbers in §3.6 are a starting point to be tuned after a week of real use.
- The 60 s calm period, the 10 min Ignore cooldown, and the 3-day half-life and 2 h learning for usual usage.
- When the Mac is strained and nobody is to blame, there is a header line only: no bark and no mood change.
- Usual usage lives in a JSON file in Application Support, not UserDefaults, because it is larger and written more often.
- Memory pressure is polled with `sysctl` per tick instead of a `DispatchSource` event, so it fits the tick model and is easy to fake.
- Custom limits keep the other settings of the stop they were edited from, and old custom values get the rest from Balanced.
- Progress counts time over, so the clock stops while calm, and an alert fires only on a tick where the entity is over.
- Ignore survives sleep/wake and pause, but not a relaunch.
- Strain and runaway each keep their own over-time, and the breach shows whichever is further along.
- The work goes on a `mac-strain` branch, with compile-only coordinator changes allowed in WP2 and WP4 so every package builds.
