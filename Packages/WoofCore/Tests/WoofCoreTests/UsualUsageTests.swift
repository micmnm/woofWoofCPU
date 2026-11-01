import Foundation
import Testing
@testable import WoofCore

@Suite struct UsualUsageTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var key: EntityKey { entity("a").key }

    func learn(_ usual: inout UsualUsage, hours: Double, tick: TimeInterval = 5, from start: Date? = nil, value: (Int) -> Double) {
        let n = Int(hours * 3_600 / tick)
        for i in 0..<n {
            let at = (start ?? t0).addingTimeInterval(Double(i) * tick)
            usual.record([entity("a", cpu: value(i))], elapsed: tick, maxElapsed: 3_600 * 24 * 7, at: at)
        }
    }

    @Test func notLearnedBeforeTwoHours() {
        var usual = UsualUsage()
        learn(&usual, hours: 1) { _ in 50 }
        #expect(usual.usualHigh(key, .cpu) == nil)
        learn(&usual, hours: 1) { _ in 50 }
        #expect(usual.usualHigh(key, .cpu) != nil)
    }

    @Test func steadyValueUsualHighIsAtLeastQuarterAbove() throws {
        var usual = UsualUsage()
        learn(&usual, hours: 3) { _ in 50 }
        let high = try #require(usual.usualHigh(key, .cpu))
        #expect(abs(high - 62.5) < 0.1)
    }

    @Test func noisyValueUsesTwoSigma() throws {
        var usual = UsualUsage()
        learn(&usual, hours: 3) { $0 % 2 == 0 ? 0 : 100 }
        let high = try #require(usual.usualHigh(key, .cpu))
        #expect(high > 125)
    }

    @Test func decayFollowsHalfLife() throws {
        var usual = UsualUsage()
        learn(&usual, hours: 30 * 24, tick: 3_600) { _ in 100 }
        learn(&usual, hours: 72, tick: 3_600, from: t0.addingTimeInterval(31 * 86_400)) { _ in 200 }
        #expect(abs(try #require(usual.mean(key, .cpu)) - 150) < 5)
    }

    @Test func gapsLongerThanMaxElapsedAreSkipped() {
        var usual = UsualUsage()
        usual.record([entity("a", cpu: 50)], elapsed: 3_600, maxElapsed: 15, at: t0)
        #expect(usual == UsualUsage())
    }

    @Test func recordsBothResources() throws {
        var usual = UsualUsage()
        for i in 0..<1_500 {
            usual.record([entity("a", cpu: 10, memory: 2 * gb)], elapsed: 5, maxElapsed: 15, at: t0.addingTimeInterval(Double(i) * 5))
        }
        #expect(abs(try #require(usual.usualHigh(key, .memory)) - 2.5 * Double(gb)) < 1)
    }

    @Test func pruneDropsEntitiesNotSeen() {
        var usual = UsualUsage()
        usual.record([entity("old", cpu: 1)], elapsed: 5, maxElapsed: 15, at: t0)
        usual.record([entity("new", cpu: 1)], elapsed: 5, maxElapsed: 15, at: t0.addingTimeInterval(1_000))
        usual.prune(notSeenSince: t0.addingTimeInterval(500))
        var expected = UsualUsage()
        expected.record([entity("new", cpu: 1)], elapsed: 5, maxElapsed: 15, at: t0.addingTimeInterval(1_000))
        #expect(usual == expected)
    }

    @Test func forgetAllEmpties() {
        var usual = UsualUsage()
        usual.record([entity("a", cpu: 1)], elapsed: 5, maxElapsed: 15, at: t0)
        usual.forgetAll()
        #expect(usual == UsualUsage())
    }

    @Test func codableRoundTrip() throws {
        var usual = UsualUsage()
        learn(&usual, hours: 3) { _ in 50 }
        let decoded = try JSONDecoder().decode(UsualUsage.self, from: JSONEncoder().encode(usual))
        #expect(decoded == usual)
        #expect(decoded.usualHigh(key, .cpu) != nil)
    }

    @Test func storeLoadsEmptyFromCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("usual.json")
        try Data("nope".utf8).write(to: url)
        #expect(UsualUsageStore(url: url).load() == UsualUsage())
    }

    @Test func storeLoadsEmptyFromMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("usual.json")
        #expect(UsualUsageStore(url: url).load() == UsualUsage())
    }

    @Test func storeSaveThenLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsualUsageStore(url: dir.appendingPathComponent("sub/usual.json"))
        var usual = UsualUsage()
        learn(&usual, hours: 3) { _ in 50 }
        try store.save(usual)
        #expect(store.load() == usual)
    }
}
