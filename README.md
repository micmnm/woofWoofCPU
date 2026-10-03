# woofWoofCPU

A macOS menu bar dog that watches your apps and processes. When one hogs CPU or memory for too long, it barks and lets you Quit (⌥ Kill), Snooze or Ignore it.

## What it does

- **Watches** every app of yours (helper processes grouped under their app) and standalone processes, for CPU and memory.
- **Escalates** when something stays over its limit: the dog naps, sniffs (?), growls (orange !!), then **barks** — a red dog, a real bark, and reminder barks at +10/+30/+90 s. It never pops anything up on its own.
- **Click the dog** for the live top list; while it's barking the popover opens in alert mode with the culprit first. Per app or per process: **Quit** (hold ⌥ for **Kill**), **Snooze** (15 min / 1 h / until tomorrow), **Ignore**, **Always ignore**. Dismissing a bark makes the dog sulk; quitting the hog makes it proud.
- **Settings:** sensitivity slider (Chill ↔ Paranoid) with exact Advanced limits, check interval (2/5/10/30 s), rows shown, mute, launch at login, skin, ignore list and snoozes. Right-click the dog to pause watching or quit.
- **Skins:** Symbol dog (default), Pixel symbol dog, the original Pixel dog, Shiba.
- **Light on the Mac:** about 0.7 % of one core while calm.

Watches only your own processes (system/other users' processes need privileges). No network monitoring yet.

## Docs

- [Design spec](docs/superpowers/specs/2026-10-01-woofwoofcpu-design.md) — the authority for behaviour
- [Decisions log](docs/decisions.md) — what was decided and why
- [Manual checks](docs/manual-checks.md) — UI checklist and what's still unverified
- [v1 implementation plan](docs/superpowers/plans/2026-10-01-woofwoofcpu-v1.md)
- [Research on similar apps](docs/research/2026-10-01-similar-apps.md)
- [CLAUDE.md](CLAUDE.md) — working notes for AI-assisted development

## Build & run

Requires Xcode (at `/Applications/Xcode.app`) and XcodeGen (`brew install xcodegen`).

    make test        # WoofCore and MiawCore unit tests
    make run         # generate the Xcode project, build, launch the menu bar app
    make install     # copy to /Applications (needed for reliable launch at login)

To see the dog bark quickly: set Settings → Sensitivity to **Paranoid** (CPU > 50% for 1 min), then run `scripts/hog.sh cpu 120`.

## Making the dog bark

`miawMiawCPU` is a companion stress toy (in `Tools/miawMiawCPU`) that loads the Mac on purpose. All load runs inside its own process, so it shows up as "miawMiawCPU" in the dog's list and the dog's Quit / ⌥ Kill ends it.

    make miaw                        # builds bin/miawMiawCPU
    bin/miawMiawCPU demo bark        # 2 cores at 100% for 4 min: the dog barks on Balanced
    bin/miawMiawCPU demo spike       # 30 s bursts for 6 min: too short to bark
    bin/miawMiawCPU demo ramp        # 2 cores climbing from 10% to 100% over 5 min: sniff, growl, bark

Or build your own: start in 30 s, ramp 4 cores from 20% to 90% for 3 min, three times, 10 min apart:

    bin/miawMiawCPU cpu --in 30s --cores 4 --load 90 --pattern ramp --for 3m --every 10m --times 3

`bin/miawMiawCPU help` lists everything, including `mem --gb G` for memory. `scripts/hog.sh` still works for quick checks.

## Credits

The bark is "[Barking of a dog](https://commons.wikimedia.org/wiki/File:Barking_of_a_dog.ogg)" by Amada44, Wikimedia Commons, licensed [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). It was trimmed, loudness-normalized and (for the Shiba) pitched up; the derived sounds in `WoofWoofCPU/Resources/Sounds` are likewise CC BY-SA 3.0.

Dog and badge glyphs: Apple SF Symbols.
