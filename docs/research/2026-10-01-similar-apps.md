# Similar apps — research notes

Date: 2026-10-01. Popularity figures are approximate (from search snippets).

## Menu bar system monitors

| App | Price | Per-app sustained alerts? | Actions | Notes |
|---|---|---|---|---|
| **Stats** (github.com/exelban/stats) | Free, MIT, ~42k★ | No — alerts on module totals; v3.0.4 added a duration threshold against spikes | Kill from CPU top list (SIGTERM) | Network module uses `nettop` → repeated high-CPU complaints (#536, #606). "Group processes by app" closed as not planned (#1972). |
| **iStat Menus 7** (Bjango) | ~$12 | No — system-total rules ("CPU > 60% for > 10 s") | None | Premium standard; sticky or banner alerts. |
| **MenuMeters** | Free, ~3.1k★ | No | None | Old-school graphs. |
| **CleanMyMac Menu** | Subscription | Totals; flags apps > 20% CPU | Quit on hover | **List freezes while hovered** so clicks land on the right row. |
| **Activity Monitor** | Built-in | No alerts | Quit / Force Quit | Energy Impact is a good per-app laptop metric. |

## Runaway-process tools

| App | Price | Sustained per-process? | Actions | Notes |
|---|---|---|---|---|
| **App Tamer** (St. Clair) | $14.95 | Yes: "X% for longer than Y s" | Allow for now / slow or stop (SIGSTOP) / ignore forever | Closest commercial match. Grey→yellow→red menu icon. Its docs warn that low thresholds raise App Tamer's own CPU use. |
| **Hogwatch** (GitHub) | Free | Yes: 90% for 30 min | Kill / Force kill / Mute | Hysteresis (3 samples below threshold to reset), sleep resets tracking, 1 h re-alert cooldown. Tracks per PID, so helpers show up separately. |
| **hw_activity_monitor** (GitHub) | Free | Yes, grouped by executable | Notify only | Uses rusage deltas, not `ps` %CPU. Safelist for compilers and VMs. JSONL log. |
| **Quitter** (Marco Arment) | Free | No (rule is idle time) | Hide / Quit | Not sandboxable. Shows people like a simple per-app rule list. |
| **Process Lasso** (Windows) | Freemium | Yes, automatic | Lowers priority | Gentle middle ground between ignore and kill; the foreground app is exempt. |

## Playful character apps

- **RunCat:** a cat runs faster as CPU rises. ~4.5★ on the Mac App Store; the Windows port has ~10k★. Sells extra runners in-app. Loved for at-a-glance CPU without numbers. It only shows totals and offers no actions.
- **Neko clones** (oneko-swift and others): nostalgia, tiny size, idle animations. oneko-swift includes a dog sprite.
- **Bongo Cat** (Steam): huge audience; reacts to what you do; collectible cosmetics.
- **No playful app alerts on runaway processes.**

## Per-process network feasibility (for later)

- **`nettop`:** built-in but CPU-heavy; Apple DTS has acknowledged this (forums thread 757294).
- **NetworkStatistics.framework** (private, `NStatManagerCreate`): what Activity Monitor and nettop use. Per-connection byte counts are converted to per-PID deltas. Private API: no Mac App Store, and it may break on OS updates.
- **Network Extension** (Little Snitch, TripMode): needs a system extension and an entitlement. Too heavy for monitoring alone.
- **Verdict:** feasible through NStat, but costlier and more fragile than CPU/memory. CPU and memory are cheap via `proc_pid_rusage`.

## Ideas adopted in the design

- Hysteresis, wake resets and once-per-breach alerting (Hogwatch, hw_activity_monitor).
- Group helpers under their app (the gap Stats left).
- rusage deltas plus `phys_footprint` instead of `ps`.
- Ambient escalation in the menu bar icon (RunCat, App Tamer).
- Hover-freeze list (CleanMyMac); sparkline with a limit line.
- Always-ignore list (App Tamer's "ignore forever").
- Adaptive polling to keep self-cost low.

## Ideas parked

- Pause/throttle via SIGSTOP and lowering priority (App Tamer, Process Lasso).
- Cosmetic packs (RunCat).
- Naughty-list history (hw_activity_monitor's JSONL log).

## Pitfalls to remember

- Builds, exports, indexing, backups and VMs are legitimate hogs, so default windows must not be too short.
- Alert fatigue.
- The monitor's own CPU use.
- PID reuse.
- A paused (SIGSTOP) app looks hung.
- Processes owned by other users need privileges to signal.

## Sources

github.com/exelban/stats · bjango.com/mac/istatmenus · github.com/yujitach/MenuMeters · macpaw.com (CleanMyMac knowledge base) · stclairsoft.com/AppTamer · github.com/pierot/hogwatch · github.com/MartinMikusat/hw_activity_monitor · marco.org/2016/05/02/quitter · bitsum.com/process-lasso-faq · apps.apple.com RunCat · github.com/Kyome22/RunCat365 · github.com/oneko-swift/oneko-swift · store.steampowered.com Bongo Cat · developer.apple.com/forums/thread/757294 · github.com/mo2g/traffic-monitoring · obdev.at Little Snitch · radiosilenceapp.com/private-eye
