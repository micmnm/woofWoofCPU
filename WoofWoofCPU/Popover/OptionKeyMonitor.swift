import AppKit
import Observation

/// Polls the ⌥ key while the popover is open. Polling `NSEvent.modifierFlags` needs no
/// Accessibility permission, unlike a global flagsChanged monitor for a non-active app.
@MainActor
@Observable
final class OptionKeyMonitor {
    private(set) var isOptionDown = false
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let down = NSEvent.modifierFlags.contains(.option)
                if self?.isOptionDown != down { self?.isOptionDown = down }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isOptionDown = false
    }
}
