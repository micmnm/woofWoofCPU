# Manual checks

The app target has no UI tests. Run these on the installed app (`make install`, then relaunch) after UI changes. Use `bin/miawMiawCPU` (`make miaw`) to create load; Settings → Sensitivity **Paranoid** makes barks come within a few minutes (a runaway process barks after 3 min, strain barks after 1–2 min).

## Status

Verified on screen during development: sniffing → growling → red barking dog with no popover; click opens the alert popover; dismiss → sulking; crisp Symbol and Pixel symbol skins on a 1× display; idle CPU 0.74 % (Release).

The strain-aware barking items below have not been checked on screen yet: the strain line, no-culprit header, sparkline bar, Forget what's usual dialog, new copy and breed lines.

Still to check by hand:
- [ ] Breed change in Settings while watching is paused reaches the menu bar dog.
- [ ] Launch at login: enable, approve in System Settings if asked, log out and in; switching it off while approval is pending works.
- [ ] Right-click menu shows "Pause watching ▸" with 30 min / 1 h / until resumed; Resume appears while paused.
- [ ] Popover on a very short screen clips only at the bottom.
- [ ] Popover over a full-screen app and on another Space.
- [ ] Quit an app with unsaved changes (e.g. TextEdit): save prompt appears, row shows "Asking politely…" then "Still here — hold ⌥ to Kill"; nothing is killed automatically.
- [ ] Quit Xcode from the list while a Terminal build runs: Xcode gets a polite quit.
- [ ] Sleep the Mac during a running hog: after wake the dog sniffs again rather than barking instantly.

Strain-aware barking (Balanced, on the MacBook Air; `make miaw` for the load):
- [ ] Calm Mac, busy browser: normal browsing plus a video for 15 min and the dog never barks.
- [ ] Runaway: `bin/miawMiawCPU cpu --cores 1 --for 15m` makes the dog bark after about 10 min (about 5 min on battery) with the runaway copy, and the app row opens with the stuck process first.
- [ ] CPU strain: `bin/miawMiawCPU cpu --cores all --for 6m` pushes the Mac above 75% busy, and the dog barks at miawMiawCPU after 3 min.
- [ ] Memory strain (switch to Alert): `bin/miawMiawCPU mem --gb 5 --for 10m` takes memory pressure to warning, the dog barks at miawMiawCPU after 3 min, and the header says "Your Mac is short on memory."
- [ ] Ignore sticks: Ignore during the memory strain run, let memory dip briefly, and no new bark comes within 10 min.
- [ ] Snooze end: snooze 15 min with the hog still running; no instant bark when the snooze ends, and it barks one window later.
- [ ] Self-cost stays below 1% of one core while calm (Activity Monitor, 5 min).

## Full checklist

1. `bin/miawMiawCPU demo bark` on Paranoid: sniff (≈ immediately), growl (≈ half the 3 min runaway window), red barking dog + bark sound with runaway copy; reminder barks at +10/+30/+90 s; no popover opens by itself.
2. Click the barking dog: popover in alert mode, culprit first. Hold ⌥: Quit turns red "Kill"; click it → the dog is proud (heart) ~10 s, then naps.
3. Bark again, then press Esc: the dog sulks (turned away + rain cloud), no more barks for that episode.
4. Snooze 15 min on a barking row: back to napping; Settings → Exceptions shows the snooze; cancel it there.
5. Click the dog with a browser open: it is one row that expands to its helpers; quit a single helper.
6. `bin/miawMiawCPU mem --gb 8 --for 6m` on Paranoid: once memory pressure reaches warning, memory bark line and "Your Mac is short on memory." under it.
7. Switch breeds (Classic, 8-bit classic, Pixel pup, Shiba): menu bar dog, popover portrait and in-app icon change; check light and dark menu bars.
8. Pause 30 min from the popover footer: dog naps, header says "Off duty until …"; Resume works; Mute silences barks.
9. Settings → Patrol on Snoozy (hold ⌥: "every 30 s"): detection gets coarser, bark timing stays in seconds.
10. `bin/miawMiawCPU mem --gb 8 --for 6m` on Paranoid until it barks (memory pressure must reach warning), then ⋯ → Bowl → Huge on that row: the dog calms at once, the subtitle reads "· Huge bowl" and the dashed line moves up. Open ⋯ → Bowl, then press and release ⌥: the bowls switch to "up to … GB" and back while the menu stays open. Settings → Exceptions lists it; set it back to Regular to remove it.
11. Leave the app idle 5 min: Activity Monitor shows < 1 % CPU.

## Open questions

- Should closing an alert popover count as Ignore (dog naps) instead of sulking?
- Art: the sulking rain cloud loses its rain on the coarse 1× pixel grid.
