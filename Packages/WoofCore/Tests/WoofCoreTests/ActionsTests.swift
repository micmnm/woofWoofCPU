import Darwin
import Testing
@testable import WoofCore

@Suite struct ProcessActionsTests {
    let app = Entity(
        key: .app(bundleID: "com.example.App"),
        displayName: "App",
        bundlePath: "/Applications/App.app",
        mainPID: 10,
        members: [
            sample(11, path: "/Applications/App.app/Contents/Frameworks/H.app/Contents/MacOS/H", cpu: 90),
            sample(10, path: "/Applications/App.app/Contents/MacOS/App", cpu: 5),
        ],
        ownedByCurrentUser: true
    )

    @Test func quitPrefersPoliteAppQuit() {
        let signaller = FakeSignaller()
        signaller.runningApps = [10]
        #expect(ProcessActions(signaller: signaller).quit(app) == .sent)
        #expect(signaller.appQuits == [10])
        #expect(signaller.sent.isEmpty)
    }

    @Test func quitFallsBackToSIGTERMWhenAppQuitUnavailable() {
        let signaller = FakeSignaller()
        _ = ProcessActions(signaller: signaller).quit(app)
        #expect(signaller.sent.map(\.signal) == [SIGTERM, SIGTERM])
    }

    @Test func killSendsSIGKILLToMainFirstThenHelpers() {
        let signaller = FakeSignaller()
        _ = ProcessActions(signaller: signaller).kill(app)
        #expect(signaller.sent.map(\.signal) == [SIGKILL, SIGKILL])
        #expect(signaller.sent.map(\.pid) == [10, 11])
    }

    @Test func singleProcessQuitAndKill() {
        let signaller = FakeSignaller()
        let actions = ProcessActions(signaller: signaller)
        _ = actions.quit(app.members[0])
        _ = actions.kill(app.members[0])
        #expect(signaller.sent.map(\.signal) == [SIGTERM, SIGKILL])
        #expect(signaller.sent.map(\.pid) == [11, 11])
    }

    @Test func errorsAreCombined() {
        #expect(ProcessActions.combine([.sent, .notAllowed]) == .notAllowed)
        #expect(ProcessActions.combine([.alreadyGone, .alreadyGone]) == .alreadyGone)
        #expect(ProcessActions.combine([.sent, .alreadyGone]) == .sent)
        #expect(ProcessActions.combine([.failed(5), .sent]) == .failed(5))
    }

    @Test func otherUsersEntitiesCannotBeActedOn() {
        let actions = ProcessActions(signaller: FakeSignaller())
        #expect(actions.canAct(on: app))
        #expect(!actions.canAct(on: entity("root-thing", uid: 0)))
        #expect(!actions.canAct(on: sample(1, uid: 0), currentUID: 501))
    }

    @Test func posixSignallerReportsGoneAndNotAllowed() {
        let signaller = PosixSignaller(quitApp: { _ in false })
        #expect(signaller.send(0, to: 99_999_999) == .alreadyGone)
        #expect(signaller.send(0, to: 1) == .notAllowed) // launchd is root
        #expect(signaller.isAlive(getpid()))
    }

    /// kill(0, …) hits our own process group and kill(-1, …) every process we own.
    @Test func posixSignallerRefusesNonPositivePIDs() {
        let signaller = PosixSignaller(quitApp: { _ in false })
        // Signal 0 only checks permissions, so this is harmless even without the guard.
        #expect(signaller.send(0, to: 0) == .failed(EINVAL))
        #expect(signaller.send(0, to: -1) == .failed(EINVAL))
        #expect(!signaller.isAlive(0))
        #expect(!signaller.isAlive(-1))
    }
}
