# woofWoofCPU

A macOS menu bar dog that watches your apps and processes. When one hogs CPU or memory for too long, it barks and lets you Quit (⌥ Kill), Snooze or Ignore it.

- Design spec: [docs/superpowers/specs/2026-10-01-woofwoofcpu-design.md](docs/superpowers/specs/2026-10-01-woofwoofcpu-design.md)
- Research on similar apps: [docs/research/2026-10-01-similar-apps.md](docs/research/2026-10-01-similar-apps.md)

## Build & run

Requires Xcode (at `/Applications/Xcode.app`) and XcodeGen (`brew install xcodegen`).

    make test        # WoofCore unit tests
    make run         # generate the Xcode project, build, launch the menu bar app
    make install     # copy to /Applications (needed for reliable launch at login)

To see the dog bark quickly: set Settings → Sensitivity to **Paranoid** (CPU > 50% for 1 min), then run `scripts/hog.sh cpu 120`.
