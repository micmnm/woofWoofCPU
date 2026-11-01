import Foundation

/// The learned usage lives in a JSON file, not UserDefaults: it is larger and written more often.
public struct UsualUsageStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/woofWoofCPU/usual.json`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("woofWoofCPU/usual.json")
    }

    /// Empty when the file is missing or unreadable.
    public func load() -> UsualUsage {
        guard let data = try? Data(contentsOf: url),
              let usual = try? JSONDecoder().decode(UsualUsage.self, from: data) else { return UsualUsage() }
        return usual
    }

    public func save(_ usual: UsualUsage) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(usual).write(to: url, options: .atomic)
    }
}
