import WoofCore

/// The dog's funny lines. `{app}`, `{value}`, `{duration}` are substituted.
enum Lines {
    static func line(mood: DogMood, resource: Resource?, app: String?, value: String, duration: String, seed: Int) -> String {
        let bank: [String]
        switch (mood, resource) {
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
}
