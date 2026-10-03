# Manual checks

The app target has no UI tests. Run these on the installed app (`make install`, then relaunch) after UI changes. Use `bin/miawMiawCPU` (`make miaw`) to create load; Settings → Sensitivity **Paranoid** makes barks come within about a minute.

## Status

Verified on screen during development: sniffing → growling → red barking dog with no popover; click opens the alert popover; dismiss → sulking; crisp Symbol and Pixel symbol skins on a 1× display; idle CPU 0.74 % (Release).

Still to check by hand:
- [ ] Skin change in Settings while watching is paused reaches the menu bar dog.
- [ ] Launch at login: enable, approve in System Settings if asked, log out and in; switching it off while approval is pending works.
- [ ] Right-click menu shows "Pause watching ▸" with 30 min / 1 h / until resumed; Resume appears while paused.
- [ ] Popover on a very short screen clips only at the bottom.
- [ ] Popover over a full-screen app and on another Space.
- [ ] Quit an app with unsaved changes (e.g. TextEdit): save prompt appears, row shows "Asking politely…" then "Still here — hold ⌥ to Kill"; nothing is killed automatically.
- [ ] Quit Xcode from the list while a Terminal build runs: Xcode gets a polite quit.
- [ ] Sleep the Mac during a running hog: after wake the dog sniffs again rather than barking instantly.

## Full checklist

1. `bin/miawMiawCPU demo bark`: sniff (≈ immediately), growl (≈ half the window), red barking dog + bark sound; reminder barks at +10/+30/+90 s; no popover opens by itself.
2. Click the barking dog: popover in alert mode, culprit first. Hold ⌥: Quit turns red "Kill"; click it → the dog is proud (heart) ~10 s, then naps.
3. Bark again, then press Esc: the dog sulks (turned away + rain cloud), no more barks for that episode.
4. Snooze 15 min on a barking row: back to napping; Settings → Ignore list shows the snooze; cancel it there.
5. Click the dog with a browser open: it is one row that expands to its helpers; quit a single helper.
6. `bin/miawMiawCPU mem --gb 8 --for 6m` on Paranoid: memory bark line.
7. Switch skins (Symbol, Pixel symbol, Pixel, Shiba): menu bar dog, popover portrait and in-app icon change; check light and dark menu bars.
8. Pause 30 min from the popover footer: dog naps, header says "Off duty until …"; Resume works; Mute silences barks.
9. Settings → Check every 30 s: detection gets coarser, bark timing stays in seconds.
10. Leave the app idle 5 min: Activity Monitor shows < 1 % CPU.

## Open questions

- Should closing an alert popover count as Ignore (dog naps) instead of sulking?
- Art: the sulking rain cloud loses its rain on the coarse 1× pixel grid.
