# Bark When the Mac Is Hurting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The dog barks only when the Mac is strained and a specific app causes it, or when one process runs away. Ignore and Snooze stop re-barking.

**Architecture:** WoofCore gains a machine-state reader (`Sampling/`), a per-app usual-usage model (`Rules/UsualUsage`), and a pure `Judge` that turns (entity, machine, limits, usual) into verdicts. `BreachTracker` accumulates time-over per reason; `MoodEngine` keeps pair mutes that survive timer resets. The app wires it in and shows a strain line.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, AppKit + SwiftUI, libproc / Mach host APIs / IOKit power sources, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-01-mac-strain-barking-design.md` (amends `docs/superpowers/specs/2026-10-01-woofwoofcpu-design.md`). Read both, plus `CLAUDE.md`.

## Global Constraints

- Swift 6 language mode, strict concurrency, **zero warnings**, macOS 14 deployment target, no third-party dependencies.
- Build and test only through the Makefile: `make test` (`FILTER=<Suite>` to narrow) and `make build`. Never call `swift`/`xcodebuild` directly. Never `cd`; use absolute paths.
- TDD for WoofCore: failing test first. Tests use Swift Testing (`@Suite`, `@Test`, `#expect`), with helpers in `Packages/WoofCore/Tests/WoofCoreTests/TestSupport.swift` (`entity(...)`, `sample(...)`, `gb`).
- No new private API. Allowed: `sysctl`, `host_statistics`, `ProcessInfo`, IOKit `IOPS*`.
- Comments: short, only what the code can't say, and no history narration.
- Commits: one line, no body, no trailers, no mention of Claude, Anthropic or model names. Commit on branch `mac-strain` (or your worktree branch). Never push.
- All work happens on branch `mac-strain`. `make test` and `make build` must pass after every task. Tasks 2 and 6 may make **compile-only** edits to `WoofWoofCPU/App/AppCoordinator.swift` and `AppDelegate.swift` with no behaviour change.

## Review Focus

1. **Sleep with the lid closed mid-breach (Air):** on wake, nothing barks until a fresh window, and Ignores still hold. Covered by Task 1's wake test.
2. **Host CPU counters wrap or go backwards:** `cpuBusy` must be 0 for that tick, never negative or NaN. Covered by Task 2.
3. **Entity disappears and returns** (an app relaunched within 10 min of an Ignore): it is still ignored, keyed by bundle id. Covered by Task 1.
4. **Corrupt or old `usual.json`, or an old custom limits blob in UserDefaults:** the app starts, with no crash and no lost settings. Covered by Tasks 3 and 4.
5. **No readable culprit while strained** (the load is in root processes): no bark, and the header says the Mac is strained. Covered by Task 6's test (`Judge` returns no verdicts while strain is true) and Task 7's header.

---

### Task 1: Calm by time, sticky Ignore, snooze-end restart (WP1)

**Files:**
- Modify: `Packages/WoofCore/Sources/WoofCore/Rules/BreachTracker.swift`, `Mood/MoodEngine.swift`, `Pipeline/WatchPipeline.swift`
- Modify (compile-only): `WoofWoofCPU/App/AppCoordinator.swift`. `ignore(_:)` and `setBowl` call the new `ignore(_ key:now:)`, and `publish` uses `isIgnored(_ key:)`.
- Test: `Packages/WoofCore/Tests/WoofCoreTests/RulesTests.swift`, `MoodTests.swift`, `PipelineTests.swift`

**Interfaces:**
- Produces:
  - `BreachTracker.calmPeriod: TimeInterval = 60`.
  - `Breach` gains `overTime: TimeInterval` and `isOver: Bool`. `progress = min(1, overTime / window)`. `since` is kept as the episode start.
  - `BreachTracker.restart(entity: EntityKey, now: TimeInterval)` zeroes `overTime` for that entity's breaches.
  - `MoodEngine.ignoreCooldown: TimeInterval = 600`.
  - `MoodEngine.ignore(_ key: BreachKey, now: TimeInterval)`.
  - `MoodEngine.isIgnored(_ key: BreachKey) -> Bool`.
  - `MoodEngine.reset()` keeps pair mutes.
  - `ignore(breachID:)` and `isIgnored(breachID:)` are removed.

- [ ] **Step 1: Write the failing tests**
  - `RulesTests.BreachTrackerTests`:
    - `breachEndsAfterSixtySecondsCalmAtTwoSecondTicks`: over at t=0, then calm from t=2. The breach is still present at t=60 and gone at t=62.
    - Same at 30 s ticks: still present at t=30, gone at t=90 (calm since 30, 60 s elapsed).
    - `progressCountsOnlyTimeOver`: over 0…30 (window 60), calm 30…50, over again at 52. Progress at t=52 is 32/60. On the calm ticks `isOver == false` and progress is frozen at 0.5.
    - `restartZeroesOverTime`.
    - Replace `breachEndsAfterThreeCalmTicks` with the 60 s test. Keep the hysteresis test as is: the band is still 0.9 in Task 1.
  - `MoodTests`:
    - `ignoreSurvivesANewEpisode`: ignore key K at t=0; K's breach ends; a new breach id for K starts at t=100 with progress 1, so no alert.
    - `ignoreExpiresAfterTenCalmMinutes`: K absent from breaches from t=0 to t=600 → at t=601 a new K breach at progress 1 alerts.
    - `ignoreSurvivesReset`: after `reset()`, `isIgnored(K)` is still true.
    - `ignoreSurvivesPause`: paused for 3600 s, then unpaused: still ignored.
    - `alertNeedsIsOver`: a breach with progress 1 and `isOver == false` emits no alert.
  - `PipelineTests`:
    - `snoozeEndRestartsTheWindow`: an entity is over with progress 1 while muted; the next step is unmuted → no new alert, progress 0. One window later it alerts.
    - `wakeResetKeepsIgnore`: after `resetTimers()` an ignored key stays ignored.

- [ ] **Step 2: Run them to verify they fail**
  Run: `make test FILTER=BreachTrackerTests` (then `MoodEngineTests` and the pipeline suite). Expected: they fail to compile or fail the assertions.

- [ ] **Step 3: Implement**
  - **Tracker state:** `id, since, lastTick, overTime, calmSince: TimeInterval?, lastValue`.
    - On an over tick: `overTime += now - lastTick` (the start tick adds 0), `calmSince = nil`.
    - On a calm tick: set `calmSince` if it is nil. The breach ends when `now - calmSince >= calmPeriod`.
  - **Engine:** `ignored: [BreachKey: TimeInterval]` holds the last uptime the key had a breach.
    - Refresh the entries present in `breaches`. While paused, refresh all of them.
    - Drop an entry when `now - last >= ignoreCooldown`.
    - `active` excludes ignored keys. `newAlerts` also requires `isOver`.
  - **Pipeline:** keep `mutedLastTick: Set<EntityKey>`. On a transition from muted to unmuted, call `tracker.restart(entity:now:)` before the engine sees the breaches. Do this in both `step` and `reevaluate`.

- [ ] **Step 4: Run all tests and the build**
  Run: `make test`, then `make build`. Expected: all pass, zero warnings.

- [ ] **Step 5: Commit**
  `git commit -m "End breaches after 60 s calm, count only time over, keep Ignore per app until 10 calm minutes, restart the window when a snooze ends"`

### Task 2: Machine state reader (WP2)

**Files:**
- Create: `Packages/WoofCore/Sources/WoofCore/Sampling/MachineState.swift` (types and `HostCPUCalculator`), `Sampling/LiveMachineStateSource.swift`
- Modify:
  - `Sampling/Sampler.swift`.
  - `Packages/WoofCore/Package.swift`: the WoofCore target gets `linkerSettings: [.linkedFramework("IOKit")]`.
  - Compile-only: `WoofWoofCPU/App/AppDelegate.swift:28` passes `LiveMachineStateSource()`, and `AppCoordinator.tick()` uses `.entities`.
- Test: create `Packages/WoofCore/Tests/WoofCoreTests/MachineStateTests.swift`, and add `FakeMachineSource` to `TestSupport.swift`.

**Interfaces:**
- Produces:
  - Exactly spec §5 `MachineState`, `MemoryPressure`, `ThermalLevel`, `MachineStateSource` (`read()`, `reset()`) and `HostCPUCalculator.busy(busyTicks:totalTicks:) -> Double`.
  - `public struct Snapshot: Sendable { public let entities: [Entity]; public let machine: MachineState }`.
  - `Sampler.init(source:grouper:machine: any MachineStateSource)`.
  - `Sampler.sample(now:) -> Snapshot`. `Sampler.reset()` also calls `machine.reset()`.
  - `MachineState.calm(cores:memory:)` has pressure normal, thermal nominal, not on battery, no Low Power Mode, and `cpuBusy` 0.
- `FakeMachineSource(_ states: [MachineState])` returns them in order, repeating the last one.

- [ ] **Step 1: Write the failing tests** (`MachineStateTests`)
  - `firstReadingIsZero`: `busy(busyTicks: 500, totalTicks: 1000) == 0`.
  - `deltaGivesBusyFraction`: (500, 1000) then (800, 1400) → 300/400 = 0.75.
  - `countersGoingBackwardsGiveZero`: (500, 1000) then (100, 1100) → 0. The next reading after that uses the new baseline.
  - `zeroTotalDeltaGivesZero`.
  - `resetForgetsBaseline`.
  - `pressureLevelMapping`: test the static `MemoryPressure(sysctlLevel:)`. 1 → normal, 2 → warning, 4 → critical, anything else → normal.
  - `thermalMapping`: from `ProcessInfo.ThermalState`.
  - `liveSourceReadsSaneValues`: `LiveMachineStateSource().read()` has `logicalCores > 0`, `physicalMemory > 0` and `cpuBusy` in 0…1. This is a smoke test.
  - `samplerReturnsMachineState`: a `Sampler` with `FakeSource` and `FakeMachineSource` returns the fake's state in `Snapshot.machine`.

- [ ] **Step 2: Run them to verify they fail.** Run `make test FILTER=MachineStateTests`. Expected: compile failure.

- [ ] **Step 3: Implement**
  - Pressure: `sysctlbyname("kern.memorystatus_vm_pressure_level")` as `Int32`.
  - CPU: `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, …)`. Busy is user + system + nice; total adds idle.
  - Battery: `IOPSCopyPowerSourcesInfo` + `IOPSGetProvidingPowerSourceType` == `kIOPMBatteryPowerKey`.
  - Low Power Mode and thermal state come from `ProcessInfo`.
  - `LiveMachineStateSource` is a `final class … @unchecked Sendable` holding an `OSAllocatedUnfairLock<HostCPUCalculator>`.

- [ ] **Step 4: Run `make test` and `make build`.** Expected: all pass, zero warnings.

- [ ] **Step 5: Commit** `git commit -m "Read memory pressure, thermal state, battery and whole-machine CPU each tick"`

### Task 3: Usual usage per app (WP3)

**Files:**
- Create: `Packages/WoofCore/Sources/WoofCore/Rules/UsualUsage.swift`, `Settings/UsualUsageStore.swift`
- Test: create `Packages/WoofCore/Tests/WoofCoreTests/UsualUsageTests.swift`

**Interfaces:**
- Produces:
  - `UsualUsage` as in spec §5: `record(_:elapsed:maxElapsed:at:)`, `usualHigh(_:_:) -> Double?`, `prune(notSeenSince:)`, `forgetAll()`, `halfLife = 3 * 86_400`, `learnedAfter = 2 * 3_600`.
  - `UsualUsageStore(url: URL)` with `load() -> UsualUsage` (empty on a missing or corrupt file) and `save(_:) throws` (atomic write, creating the directory).
  - `UsualUsageStore.defaultURL` is `~/Library/Application Support/woofWoofCPU/usual.json`.

- [ ] **Step 1: Write the failing tests** (`UsualUsageTests`, using values in the same units as `Entity.value(for:)`)
  - `notLearnedBeforeTwoHours`: 1 h of 5 s ticks at CPU 50 → `usualHigh` is nil. At 2 h it is not nil.
  - `steadyValueUsualHighIsAtLeastQuarterAbove`: 3 h at 50 → `usualHigh ≈ 62.5` (mean × 1.25 wins because the variance is ~0).
  - `noisyValueUsesTwoSigma`: alternate 0 and 100 for 3 h → usual high is about mean + 2σ (~150). Check `> 125`.
  - `decayFollowsHalfLife`: learn at 100 for 3 h, then record 200 for one half-life (3 days, in 1 h ticks) → mean ≈ 150 ± 5.
  - `gapsLongerThanMaxElapsedAreSkipped`: `elapsed: 3600, maxElapsed: 15` changes nothing.
  - `pruneDropsEntitiesNotSeen`: and keeps recently seen ones.
  - `codableRoundTrip`.
  - `storeLoadsEmptyFromCorruptFile`: write `"nope"` to a temp URL → `load()` is empty, no throw.
  - `storeSaveThenLoad`: round-trip through a temp directory that doesn't exist yet.

- [ ] **Step 2: Run them to verify they fail.** Run `make test FILTER=UsualUsageTests`.

- [ ] **Step 3: Implement**
  - Per (key, resource), keep a `Stat { mean, variance, observed, lastSeen }`.
  - Each record step: `alpha = 1 - exp(-ln2 * elapsed / halfLife)`; `d = x - mean`; `mean += alpha * d`; `variance = (1 - alpha) * (variance + alpha * d * d)`; `observed += elapsed`.
  - The first sample sets `mean = x`, `variance = 0`.
  - Skip when `elapsed <= 0 || elapsed > maxElapsed`.
  - `usualHigh` is nil when `observed < learnedAfter`; otherwise `max(mean + 2 * sqrt(variance), mean * 1.25)`.

- [ ] **Step 4: Run `make test`.** Expected: all pass.

- [ ] **Step 5: Commit** `git commit -m "Learn each app's usual CPU and memory with a 3-day half-life, saved to Application Support"`

### Task 4: New limits and stops (WP4, part 1)

**Files:**
- Modify: `Packages/WoofCore/Sources/WoofCore/Rules/Limits.swift`
- Test: `RulesTests.swift` (`LimitsTests`), `SettingsTests.swift`

**Interfaces:**
- Consumes: `MemoryPressure`, `ThermalLevel` (Task 2).
- Produces: `Limits` gains these fields:
  - `memoryStrainAt: MemoryPressure`
  - `cpuStrainThermal: ThermalLevel`
  - `cpuStrainBusy: Double` (0…1, plugged in)
  - `cpuShare: Double` (0…1)
  - `runawayWindow: TimeInterval`

  `cpu.threshold` is the CPU minimum (% of one core), and `memory.threshold` is the memory floor (fraction of RAM). `fed(_:)` and `thresholdValue` keep their meaning. A custom `init(from:)` fills missing new fields from `Sensitivity.balanced.limits`.

- [ ] **Step 1: Write the failing tests**
  - `stopsMatchTheSpecTable`: assert all five rows of spec §3.6 exactly. For example, Balanced is `cpu (100, 180)`, `memory (0.15, 300)`, `.warning`, `.serious`, `0.75`, `0.33`, `600`. Chill is `(200, 600)`, `(0.25, 900)`, `.critical`, `.critical`, `0.90`, `0.50`, `1800`.
  - Update `balancedIsTheSpecDefault`, `memoryThresholdScalesWithRAM` (now 0.15) and `bowlsScaleOnlyTheMemoryThreshold` to the new numbers.
  - `oldCustomLimitsStillDecode` (`SettingsTests`): build the old JSON by encoding a test-local `struct OldLimits: Codable { var cpu: Limit; var memory: Limit }` inside `LimitsSetting`'s existing encoded shape. Encode `LimitsSetting.custom` before the change to see the shape; it is `{"custom":{"_0":…}}`. Decoding yields those cpu and memory values with Balanced's other fields.

- [ ] **Step 2: Run them to verify they fail.** Run `make test FILTER=LimitsTests`.

- [ ] **Step 3: Implement** the fields, the table and the decoder.

- [ ] **Step 4: Run `make test` and `make build`.**

- [ ] **Step 5: Commit** `git commit -m "Add strain triggers, share of load and runaway window to each sensitivity stop"`

### Task 5: Judge (WP4, part 2)

**Files:**
- Create: `Packages/WoofCore/Sources/WoofCore/Rules/Judge.swift`
- Test: create `Packages/WoofCore/Tests/WoofCoreTests/JudgeTests.swift`

**Interfaces:**
- Consumes: `MachineState` (Task 2), `UsualUsage` (Task 3), `Limits` (Task 4), `Bowl`, `Entity`.
- Produces: exactly spec §5. `BreachReason` (`strain`, `runaway`), `Verdict(reason:window:)`, `Strain(memory:cpu:)`, `Judge.strain(_:_:)`, and `Judge.verdicts(_:_:machine:strain:limits:bowl:usual:continuing:) -> [Verdict]`, sorted with strain first.
  - Constants: `Judge.runawayCPU = 90`, `Judge.continuingFactor = 0.9`, `Judge.batteryBusyDrop = 0.25`.

- [ ] **Step 1: Write the failing tests** (`JudgeTests`; 8 GB and 8 cores via `MachineState.calm(cores: 8, memory: 8 * gb)` unless noted, Balanced)
  - Strain:
    - `memoryStrainAtWarning`.
    - `noMemoryStrainWhenNormal`.
    - `cpuStrainWhenThermalSerious`.
    - `cpuStrainWhenBusyAtLeast75`.
    - `batteryLowersBusyTriggerTo50`: busy 0.55, on battery → strained; plugged in → not.
    - `lowPowerModeLowersBusyTrigger`.
  - Memory:
    - `memoryCulpritNeedsStrain`: 2.4 GB with pressure normal → `[]`.
    - `workedExampleBarksAtBrowser`: pressure warning, 2.4 GB, nothing learned → `[Verdict(.strain, 300)]`.
    - `smallAppIsNoMemoryCulprit`: 1.0 GB < 1.2 GB → `[]`.
    - `bowlRaisesFloor`: Big bowl, 1.5 GB < 1.8 GB → `[]`.
    - `bottomlessNeverMemoryCulprit`.
    - `usualSuppresses`: learned usual high 3 GB, value 2.4 GB → `[]`; 3.5 GB → strain.
    - `continuingLowersFloorTenPercent`: 1.1 GB, continuing → strain (floor 1.08 GB); not continuing → `[]`.
  - CPU:
    - `cpuCulpritNeedsMinimumAndShare`: busy 0.8 (load 640%), app at 250% → share 0.39 ≥ 0.33 → strain. App at 150% → share 0.23 → `[]`.
    - `cpuShareSkippedWhenLoadZero`: thermal serious, busy 0, app at 120% → strain.
    - `noVisibleCulprit`: CPU strain, but every entity is under the minimum → `[]`.
  - Runaway:
    - `runawayOnCalmMac`: one member at 95%, Mac calm → `[Verdict(.runaway, 600)]`.
    - `runawayCountsMultiCoreJobs`: a member at 400% → runaway, per the user's decision.
    - `runawayIgnoresUsual`: learned usual high 500% → still runaway.
    - `runawayWindowHalvesOnBattery` → 300.
    - `runawayIsPerProcessNotSum`: three members at 40% each → no runaway.
    - `bothReasons`: strained, app at 300% with a member at 95% → `[strain(180), runaway(600)]`.

- [ ] **Step 2: Run them to verify they fail.** Run `make test FILTER=JudgeTests`.

- [ ] **Step 3: Implement** per spec §3.2–3.5. The CPU share test is `entity.cpuPercent / (machine.cpuBusy * Double(machine.logicalCores) * 100)` and is skipped when the denominator is 0. `continuing` multiplies the floor, minimum, share and runaway CPU by 0.9.

- [ ] **Step 4: Run `make test`.**

- [ ] **Step 5: Commit** `git commit -m "Judge apps by machine strain, share of load, usual usage and runaway processes"`

### Task 6: Tracker and pipeline on verdicts (WP4, part 3)

**Files:**
- Modify: `Packages/WoofCore/Sources/WoofCore/Rules/BreachTracker.swift`, `Pipeline/WatchPipeline.swift`
- Modify (compile-only): `WoofWoofCPU/App/AppCoordinator.swift`. `apply` passes `machine` from the snapshot and an empty `UsualUsage()`; Task 7 wires the real one.
- Test: `RulesTests.swift`, `PipelineTests.swift`

**Interfaces:**
- Consumes: `Judge`, `Verdict` (Task 5); `Snapshot` (Task 2).
- Produces:
  - `BreachTracker.update(entities: [Entity], now: TimeInterval, verdicts: (Entity, Resource, Bool) -> [Verdict]) -> [Breach]`.
  - `Breach` gains `reason: BreachReason`. Per-reason state is `overTime` and the last `window`. Breach progress is the max over reasons, and `reason` is the argmax. The 0.9 hysteresis band moves out of the tracker; it now lives in `Judge.continuing`.
  - `WatchPipeline.step(entities:machine:limits:bowls:usual:isMuted:paused:now:) -> Step`. The `physicalMemory` parameter is removed (`machine.physicalMemory` replaces it), and `Step` gains `strain: Strain`.

- [ ] **Step 1: Write the failing tests**
  - Port the existing tracker tests to a closure-driven helper.
  - `reasonsKeepTheirOwnClocks`: runaway verdict 0…480 s (window 600, progress 0.8). From 480 s strain is added (window 180). At 540 s the breach progress is max(540/600, 60/180) = 0.9 with reason runaway, and there is no jump to 1.
  - `reasonDroppingOutKeepsProgress`: strain to 0.7, then runaway only → progress stays ≥ 0.7 and the strain clock freezes.
  - Pipeline:
    - `calmMacBusyBrowserNeverBarks`: 20 helpers totalling 300% and 2.4 GB, Mac calm, 20 min of 5 s ticks → no alerts.
    - `strainedMacBarksAtCulpritAfterWindow`: pressure warning, browser at 2.4 GB → alert at 300 s, not before.
    - `stuckProcessBarksOnCalmMac`: one member at 100% → alert at 600 s.

- [ ] **Step 2: Run them to verify they fail.** Run `make test FILTER=BreachTrackerTests`.

- [ ] **Step 3: Implement.** In the pipeline, compute `Judge.strain` once per step and pass a closure that calls `Judge.verdicts` with `bowls[entity.key] ?? .regular`.

- [ ] **Step 4: Run `make test` and `make build`.** Expected: all pass, zero warnings.

- [ ] **Step 5: Commit** `git commit -m "Track breaches per reason from the judge's verdicts"`

### Task 7: App wiring, popover and settings (WP5)

**Files:**
- Modify:
  - `WoofWoofCPU/App/AppCoordinator.swift`, `App/AppDelegate.swift`.
  - `Popover/PopoverView.swift`, `Popover/EntityRow.swift`, `Popover/Lines.swift`, `Popover/Formatting.swift`.
  - `Settings/SettingsView.swift`.

**Interfaces:**
- Consumes everything from Tasks 1–6.
- Produces, on the coordinator:
  - `private(set) var machine: MachineState`.
  - `private(set) var strain: Strain`.
  - `func forgetUsual()`.
  - `func saveUsual()` (called on `applicationWillTerminate`).
- Produces, in `Lines`:
  - `static func strainLine(_ strain: Strain, machine: MachineState) -> String?`.
  - `static func noCulpritLine(strain: Strain, topApp: String?) -> String?`.
  - The runaway bank, selected when `breach.reason == .runaway`.

- [ ] **Step 1: Wire the loop**
  - `tick` stores `snapshot.machine`.
  - `apply` records `UsualUsage` (skipped while paused) with `elapsed = now - lastTickUptime` and `maxElapsed = 3 * settings.pollInterval`, then passes `usual` to `pipeline.step`.
  - Load from `UsualUsageStore(url: .defaultURL)` at `start()`, pruning entries not seen for 30 days.
  - Save when ≥ 300 s have passed since the last save, and on terminate. Log save failures with `os.Logger`.

- [ ] **Step 2: Popover**
  - Header strain line (spec §3.7 text, in that priority order).
  - The no-culprit header in list mode when strained with no active breach; `{app}` is the top entity by the strained resource.
  - "over for" uses `breach.overTime`.
  - The sparkline limit line uses the culprit threshold when the Mac is strained on that resource, or 90% for a runaway. Otherwise hide it (pass `nil`; `Sparkline.limit` becomes `Double?`).
  - A row whose breach reason is runaway opens its drill-down by default.
  - Use the personality copy from `docs/voice.md` if it exists (written by the personality review). Otherwise use spec §3.7's examples.

- [ ] **Step 3: Settings**
  - Advanced labels read "CPU: app uses more than", "for", "Memory: app holds more than", "for".
  - Exceptions gets a "Forget what's usual" button with a confirmation dialog that calls `forgetUsual()`.

- [ ] **Step 4: Verify**
  - Run `make test` and `make build` (zero warnings), then `make run`.
  - Take `screencapture -x` shots of the popover calm, and with `bin/miawMiawCPU mem --gb 5 --for 3m` running (strain line visible). Save them to the scratchpad and list the paths in your report.

- [ ] **Step 5: Commit** `git commit -m "Show when the Mac is strained, learn usual usage in the app and explain runaways in the popover"`

### Task 7b: Personality pass

**Files:**
- Modify:
  - `WoofWoofCPU/Popover/Lines.swift`, `Popover/PopoverView.swift`, `Popover/EntityRow.swift`, `Popover/Formatting.swift`.
  - `WoofWoofCPU/Settings/SettingsView.swift`.
  - `WoofWoofCPU/Skins/Skin.swift`, `SymbolSkin.swift`, `PixelSymbolSkin.swift`, `ShibaSkin.swift`, `PixelSkin.swift`.
  - `WoofWoofCPU/MenuBar/StatusItemController.swift`.
  - `Packages/WoofCore/Sources/WoofCore/Settings/SettingsStore.swift` (`SnoozeDuration.displayName`) and its test, if one asserts the names.

**Interfaces:**
- Consumes: `Breach.reason` (Task 6) and `Lines.strainLine` / `noCulpritLine` (Task 7).
- Produces:
  - `Lines.line(mood:resource:reason:app:value:duration:seed:skinID:date:)`.
  - `Skin.extraBarkLines: [String]`, with a protocol-extension default of `[]`.

- [ ] **Step 1:** Replace the banks with `docs/voice.md`'s copy.
  - Growl and bark get separate banks; runaway lines apply when the reason is `.runaway`.
  - Napping picks by `seed`; with no breach the seed is the current hour. Night and morning lines apply by hour, and the rare line at `seed % 97 == 0`.
  - The cat line applies when the app is `miawMiawCPU` and the dog is barking or growling.
  - Breed lines are appended to the bark banks via `skin.extraBarkLines`.
- [ ] **Step 2:** Apply every row of `docs/voice.md`'s "Strings to rewrite" table. Exceptions shows app names via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` plus the bundle's display name, falling back to the id.
- [ ] **Step 3:** Run `make test` and `make build` (zero warnings). Then `make run` and take `screencapture -x` shots of the popover in a barking state (`bin/miawMiawCPU demo bark`) and in list mode. Check that no header line truncates at 320 pt.
- [ ] **Step 4:** Commit: `git commit -m "Give the dog a fuller voice: split growl from bark, add runaway, strain and breed lines, and clearer labels"`

### Task 8: Docs and manual checks (WP6)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-01-woofwoofcpu-design.md` (§4.4, §4.5, §5.2, §5.3, §6, §8, §10), `docs/decisions.md`, `docs/manual-checks.md`, `README.md` (how the dog decides, in two or three sentences).

- [ ] **Step 1:** Fold the amendment into the main spec so it reads as current behaviour, not history. Set the amendment's status to "Merged into the main spec".
- [ ] **Step 2:** Add the amendment's §8 calls and the user's runaway decision to `docs/decisions.md`, in the existing format.
- [ ] **Step 3:** Add the amendment's §7 scenarios 1–7 to `docs/manual-checks.md` as unchecked items.
- [ ] **Step 4:** Commit: `git commit -m "Describe strain-aware barking in the spec, decisions log and manual checks"`

## Execution order

Run Tasks 1, 2 and 3 in parallel in separate worktrees, then merge them into `mac-strain`. After that, run Tasks 4 → 5 → 6 → 7 → 8 in sequence on `mac-strain`. The personality review runs alongside and writes `docs/voice.md` before Task 7.
