import AppKit
import WoofCore

/// Cycles the current skin's frames for the current mood on the status item button.
@MainActor
final class DogAnimator {
    private weak var button: NSStatusBarButton?
    private var skin: any Skin
    private var mood: DogMood = .napping
    private var frameIndex = 0
    private var timer: Timer?

    init(button: NSStatusBarButton?, skin: any Skin) {
        self.button = button
        self.skin = skin
        restart()
    }

    func update(mood: DogMood, skin: any Skin) {
        guard mood != self.mood || skin.id != self.skin.id else { return }
        self.mood = mood
        self.skin = skin
        restart()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        frameIndex = 0
        show()
        guard skin.frames(for: mood).count > 1 else { return }
        let interval = skin.frameDuration(for: mood)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer?.tolerance = interval / 10
    }

    private func advance() {
        frameIndex += 1
        show()
    }

    private func show() {
        let frames = skin.frames(for: mood)
        guard !frames.isEmpty else { return }
        button?.image = frames[frameIndex % frames.count]
        button?.setAccessibilityLabel("woofWoofCPU — \(mood.rawValue)")
    }
}
