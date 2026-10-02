import AppKit
import os

@MainActor
final class BarkPlayer {
    private let log = Logger(subsystem: "com.woofwoofcpu", category: "sound")
    private var current: NSSound?

    /// Plays `<name>.caf` from the app bundle, falling back to the system "Funk" sound.
    func play(_ name: String) {
        var sound = Bundle.main.url(forResource: name, withExtension: "caf").flatMap { NSSound(contentsOf: $0, byReference: true) }
        if sound == nil {
            log.debug("bark sound \(name, privacy: .public).caf not bundled; using Funk")
            sound = NSSound(named: "Funk")
        }
        guard let sound else {
            log.error("no bark sound available")
            return
        }
        current?.stop()
        current = sound
        sound.play()
    }
}
