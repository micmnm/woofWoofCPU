import Testing
@testable import MiawCore

@Suite struct DurationParsingTests {
    @Test(arguments: [
        ("90", 90), ("90s", 90), ("5m", 300), ("1h", 3600), ("1m30s", 90),
        ("2h5m", 7500), ("1h0m1s", 3601), ("0", 0), ("0s", 0),
    ])
    func parsesValidDurations(text: String, seconds: Int) {
        #expect(DurationParser.seconds(from: text) == seconds)
    }

    @Test(arguments: [
        "abc", "-5s", "5x", "", "m", "5m5m", "30s1m", "1.5m", " 5s", "5s ", "+5", "99999999999999999999h", "9999999999999999h",
    ])
    func rejectsInvalidDurations(text: String) {
        #expect(DurationParser.seconds(from: text) == nil)
    }
}
