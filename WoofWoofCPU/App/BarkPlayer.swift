import AppKit
import os

@MainActor
final class BarkPlayer {
    private let log = Logger(subsystem: "com.woofwoofcpu", category: "sound")
    private var current: NSSound?

    /// Plays `<name>.caf` from the app bundle, or the system "Funk" sound until a real bark is bundled.
    func play(_ name: String) {
        let sound = Bundle.main.url(forResource: name, withExtension: "caf").flatMap { NSSound(contentsOf: $0, byReference: true) }
            ?? NSSound(named: "Funk")
        guard let sound else {
            log.error("no bark sound available")
            return
        }
        current?.stop()
        current = sound
        sound.play()
    }
}
