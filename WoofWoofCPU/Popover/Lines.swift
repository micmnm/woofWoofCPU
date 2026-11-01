import WoofCore

/// The dog's funny lines. `{app}`, `{value}`, `{duration}` are substituted.
enum Lines {
    static func line(
        mood: DogMood, resource: Resource?, reason: BreachReason?, app: String?, value: String, duration: String, seed: Int
    ) -> String {
        let bank: [String]
        switch (mood, resource) {
        case (.barking, _) where reason == .runaway, (.growling, _) where reason == .runaway:
            bank = runaway
        case (.barking, .cpu?), (.growling, .cpu?):
            bank = [
                "{app} is chewing all the CPU!",
                "WOOF! {app} won't stop zooming around!",
                "{app} has the zoomies. {value} for {duration}.",
            ]
        case (.barking, .memory?), (.growling, .memory?):
            bank = [
                "{app} is hoarding all the kibble ({value})!",
                "{app} buried {value} of bones and won't share.",
            ]
        case (.sniffing, _):
            bank = ["Sniff sniff… {app} smells busy."]
        case (.sulking, _):
            bank = ["Fine. I'll just keep an eye on {app}. 🙄"]
        case (.proud, _):
            bank = ["Good human. 🦴", "Bad app chased off!"]
        default:
            bank = ["All quiet. Zzz…"]
        }
        let template = bank[abs(seed) % bank.count]
        return template
            .replacingOccurrences(of: "{app}", with: app ?? "Something")
            .replacingOccurrences(of: "{value}", with: value)
            .replacingOccurrences(of: "{duration}", with: duration)
    }

    static let runaway = [
        "{app} has a process stuck chewing one core.",
        "One of {app}'s helpers won't stop spinning.",
        "{app} is chasing its tail. For {duration}.",
        "{app} has a helper running in circles.",
        "Something in {app} is stuck on {value}. WOOF!",
    ]

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
