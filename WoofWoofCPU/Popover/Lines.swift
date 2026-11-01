import Foundation
import WoofCore

/// The dog's lines (see docs/voice.md). `{app}`, `{value}`, `{duration}` are substituted.
@MainActor
enum Lines {
    /// `date` picks the night, morning and rare napping lines; the popover seeds napping lines with the hour.
    static func line(
        mood: DogMood, resource: Resource?, reason: BreachReason?, app: String?, value: String, duration: String,
        seed: Int, skinID: String, date: Date
    ) -> String {
        let extra = SkinRegistry.skin(id: skinID).extraBarkLines
        let barkingOrGrowling = mood == .barking || mood == .growling
        let bank: [String]
        switch (mood, resource) {
        case _ where barkingOrGrowling && app == "miawMiawCPU":
            bank = [cat]
        case _ where barkingOrGrowling && reason == .runaway:
            bank = runaway
        case (.barking, .cpu?):
            bank = cpuBark + extra
        case (.barking, .memory?):
            bank = memoryBark + extra
        case (.growling, .cpu?):
            bank = cpuGrowl
        case (.growling, .memory?):
            bank = memoryGrowl
        case (.sniffing, _):
            bank = sniffing
        case (.sulking, _):
            bank = sulking
        case (.proud, _):
            bank = proud
        default:
            let hour = Calendar.current.component(.hour, from: date)
            if hour < 6 {
                bank = [nappingNight]
            } else if hour < 10 {
                bank = [nappingMorning]
            } else if seed % 97 == 0 {
                bank = [nappingRare]
            } else {
                bank = napping
            }
        }
        let template = bank[abs(seed) % bank.count]
        return template
            .replacingOccurrences(of: "{app}", with: app ?? "Something")
            .replacingOccurrences(of: "{value}", with: value)
            .replacingOccurrences(of: "{duration}", with: duration)
    }

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
    /// No `{app}`: the breach is already gone.
    static let proud = [
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
    static let nappingNight = "It's late. Even I'm asleep."
    static let nappingMorning = "Morning. Nothing chewed overnight."
    static let nappingRare = "Dreaming of a bottomless bowl."
    static let paused = "Off duty. Not even sniffing."
    static let cat = "A CAT?! In MY Mac?! WOOF!"

    /// Plain and fixed: the first that applies, never randomised.
    static func strainLine(_ strain: Strain, machine: MachineState) -> String? {
        if strain.memory { return "Your Mac is short on memory." }
        guard strain.cpu else { return nil }
        if machine.thermal >= .serious { return "Your Mac is running hot." }
        if machine.onBattery { return "Your Mac is working hard on battery." }
        if machine.lowPowerMode { return "Your Mac is working hard in Low Power Mode." }
        return "Your Mac is working hard."
    }

    /// The strain line sits right under this, so it doesn't repeat "short on memory".
    static func noCulpritLine(strain: Strain, topApp: String?) -> String? {
        guard strain.memory || strain.cpu else { return nil }
        guard let topApp else { return "Nobody I can see is to blame." }
        let bank = strain.memory
            ? ["Nobody's misbehaving. {app} just eats the most.", "Everyone's eating normally. {app} eats the most."]
            : ["Nobody's misbehaving. {app} is just the busiest.", "Everyone's working normally. {app} works hardest."]
        // Keyed on the name so the line doesn't flip every tick.
        return bank[topApp.count % bank.count].replacingOccurrences(of: "{app}", with: topApp)
    }
}
