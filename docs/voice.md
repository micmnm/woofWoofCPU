# The dog's voice

## Who it is

A loyal, slightly dramatic guard dog who takes the job very seriously and knows nothing about computers. It understands everything as food, territory, laps, tails and squirrels. It is proud of you, suspicious of apps, and passive-aggressive when you overrule it.

## Rules

1. **The joke carries the facts; it never replaces them.** Every bark or growl line names `{app}`, and at least one line per bank includes `{value}` or `{duration}`.
2. **Each mood has its own sound.**
   - "WOOF" in capitals only when barking. "Grrr" only when growling.
   - Sniffing asks questions. Sulking is curt and passive-aggressive.
   - Proud wags, begs for a treat and takes credit.
3. **Blame the app, never the user.** Apps are naughty, not evil. No digs at real brands.
4. **Use a plain voice wherever reading leads to a consequence.** That means the strain line, errors, Kill, tooltips and VoiceOver labels. Never joke about death near Kill ("put down", "put to sleep", "RIP").
5. **Keep it short and in the present tense.** Lines are ≤ 60 characters with a 13-character app name. At most one emoji, only in sulking or proud lines, and only at the end.

**Words it uses:** kibble, bowl, bones, chewing, zoomies, laps, tail, sniff, grrr, treat, good human, helper, core.

**Words it avoids:** kill (in jokes), die, put down, process, thread, RAM, "bad dog" aimed at the user, and exclamation marks outside barks.

## Copy banks

`{app}`, `{value}` and `{duration}` are the only placeholders. Growl and bark use separate banks. The runaway bank is used for growl and bark when `breach.reason == .runaway`.

```swift
static let cpuBark = [
    "{app} is chewing all the CPU!",
    "WOOF! {app} won't stop zooming around!",
    "{app} has the zoomies. {value} for {duration}.",
    "WOOF! {app} has been running laps for {duration}!",
    "{app} chewed the CPU like a new shoe! ({value})",
    "WOOF! {app}: {value} for {duration}!",
    "{app} chased its tail up to {value}. WOOF!",
]
static let cpuGrowl = [
    "Grrr… {app} is getting the zoomies.",
    "Grrr. {app}: {value} for {duration}.",
    "{app} is chewing on the CPU. I'm watching.",
    "Grrr… {app}, don't make me bark.",
    "{app} is pacing at {value}. Grrr.",
    "Low growl at {app}. {value} and climbing.",
]
static let memoryBark = [
    "{app} is hoarding all the kibble ({value})!",
    "{app} buried {value} of bones and won't share.",
    "WOOF! {app} ate {value} and wants seconds!",
    "{app} licked the bowl clean: {value}!",
    "WOOF! {app} won't leave the food bowl! ({value})",
    "{app} is sitting on {value} of kibble. WOOF!",
]
static let memoryGrowl = [
    "Grrr… {app} keeps eating. {value} so far.",
    "{app} is eyeing the kibble bag. ({value})",
    "Grrr. {app} has had {value}. That's plenty.",
    "{app} is burying bones again… {value}.",
    "Grrr… {app}, step away from the bowl.",
]
static let runaway = [
    "{app} has a process stuck chewing one core.",
    "One of {app}'s helpers won't stop spinning.",
    "{app} is chasing its tail. For {duration}.",
    "{app} has a helper running in circles.",
    "Something in {app} is stuck on {value}. WOOF!",
]
static let sniffing = [
    "Sniff sniff… {app} smells busy.",
    "Hmm. {app} smells like trouble.",
    "Sniff… {app} is up to something.",
    "Ears up. Keeping a nose on {app}.",
    "{app}? Sniff sniff. Just checking.",
]
static let sulking = [
    "Fine. I'll just keep an eye on {app}. 🙄",
    "Okay. {app} is fine, apparently. 🙄",
    "Not barking. Just watching {app}. Closely.",
    "I'm not mad. I'm just watching {app}.",
    "{app}, {duration} now. Not that I'm counting.",
]
static let proud = [   // no {app}: the breach is already gone
    "Good human. 🦴",
    "Bad app chased off!",
    "We did it. Mostly me.",
    "Who's a good human? You are! 🦴",
    "Back to normal. Treat, please?",
    "Threat gone. Tail: wagging.",
]
static let napping = [
    "All quiet. Zzz…",
    "Nothing to bark at. Zzz…",
    "All apps behaving. Napping on duty.",
    "Everything's calm. One eye open.",
    "Quiet. Suspiciously quiet. Zzz…",
    "No zoomies, no hoarding. Zzz…",
]
static let nappingNight = "It's late. Even I'm asleep."      // 00:00–05:59
static let nappingMorning = "Morning. Nothing chewed overnight." // 06:00–09:59
static let nappingRare = "Dreaming of a bottomless bowl."        // seed % 97 == 0
static let paused = ["Off duty. Not even sniffing."]
static let cat = "A CAT?! In MY Mac?! WOOF!"                    // when {app} is miawMiawCPU, barking or growling

// Strain line: plain, fixed, in this priority order, never randomised.
static let strainMemory   = "Your Mac is short on memory."
static let strainHot      = "Your Mac is running hot."
static let strainBattery  = "Your Mac is working hard on battery."
static let strainLowPower = "Your Mac is working hard in Low Power Mode."
static let strainBusy     = "Your Mac is working hard."

// No-culprit headline. The strain line sits right under it, so it doesn't repeat "short on memory".
static let noCulpritMemory = [
    "Nobody's misbehaving. {app} just eats the most.",
    "Everyone's eating normally. {app} eats the most.",
]
static let noCulpritCPU = [
    "Nobody's misbehaving. {app} is just the busiest.",
    "Everyone's working normally. {app} works hardest.",
]
static let noCulpritHidden = "Nobody I can see is to blame."
```

## Breed voices

Each skin may add a few lines to the bark banks. Unknown skins use only the default banks.

- **Shiba** (dramatic): "AAAA! {app}! AAAA!" · "{app} is being SO much right now."
- **Pixel** (8-bit): "{app} TOOK {value}. GAME OVER?" · "WARNING: {app} AT {value}."

## Strings to rewrite

| Where | Now | New |
|---|---|---|
| `SnoozeDuration.displayName` (menu reads "Snooze {name}") | 15 minutes / 1 hour / Until tomorrow | for 15 minutes / for 1 hour / until tomorrow |
| Row menu | Ignore this time | Ignore for now |
| Row menu | Bowl | Bowl size |
| Bottomless bowl label | never mind memory | never bark about memory |
| Kill tooltip | Force kill immediately | Force quit now. Unsaved work is lost. |
| Disabled tooltip | Owned by another user or the system | Belongs to the system or another user |
| Row status | Not allowed (owned by another user) | Not allowed: it belongs to another user |
| Row status | Failed (error N) | Couldn't quit it (error N) |
| Settings, check interval | Sniffing: … | Patrol: … |
| Settings, Advanced | CPU above (%) | CPU above (% of one core) |
| Settings, Dog tab | Skin | Breed |
| Skin names | Symbol dog / Pixel symbol dog | Classic / 8-bit classic |
| Exceptions | No snoozes. | No snoozes right now. |
| Popover subline | limit 1.6 GB for 5m | Barks at 1.6 GB after 5m (hidden while the strain line shows) |
| Disclosure, VoiceOver | Expand / Collapse | Show processes / Hide processes |
| Header portrait | (no label) | "Dog is {mood}" |
| Status item | (no label or tooltip) | "woofWoofCPU: barking at {app}" or "woofWoofCPU: {mood}" |
| Exceptions list | bundle ids (com.google.Chrome) | app names, with the id as a tooltip |

## Later (each needs new state)

- A proud line that names the app that ran off: the coordinator remembers the last ended alert's name.
- A daily proud streak ("3 hogs chased off today"): a counter in `SettingsStore`.
- A first-run hello ("Hi! I watch your apps. Click me anytime."): a launched-before flag.
