/// Parses `90`, `90s`, `5m`, `1h`, `1m30s` into whole seconds. A bare number means seconds.
/// Anything over `maxSeconds` is rejected, which keeps schedule and countdown arithmetic far from overflow.
public enum DurationParser {
    public static let maxSeconds = 7 * 24 * 3600
    private static let units: [(Character, Int)] = [("h", 3600), ("m", 60), ("s", 1)]

    public static func seconds(from text: String) -> Int? {
        parse(text).flatMap { $0 <= maxSeconds ? $0 : nil }
    }

    private static func parse(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        if text.allSatisfy(\.isASCIIDigit) { return Int(text) }

        var total = 0
        var digits = ""
        var nextUnit = 0  // units must appear once each, in h-m-s order
        for character in text {
            if character.isASCIIDigit {
                digits.append(character)
                continue
            }
            guard !digits.isEmpty, let value = Int(digits),
                  let index = units[nextUnit...].firstIndex(where: { $0.0 == character })
            else { return nil }
            let (product, overflow) = value.multipliedReportingOverflow(by: units[index].1)
            guard !overflow else { return nil }
            let (sum, sumOverflow) = total.addingReportingOverflow(product)
            guard !sumOverflow else { return nil }
            total = sum
            digits = ""
            nextUnit = index + 1
        }
        return digits.isEmpty ? total : nil
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
