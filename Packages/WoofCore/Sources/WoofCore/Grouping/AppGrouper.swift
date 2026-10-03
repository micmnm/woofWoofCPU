import Foundation

public struct AppInfo: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    /// `CFBundleExecutable`; picks the main process when several run from `Contents/MacOS/`.
    public let executableName: String?

    public init(bundleID: String, name: String, executableName: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.executableName = executableName
    }
}

public protocol AppInfoProvider: Sendable {
    func appInfo(bundlePath: String) -> AppInfo?
}

/// Reads `CFBundleIdentifier`, display name and `CFBundleExecutable` from the bundle's Info.plist, cached per path.
public final class BundleAppInfoProvider: AppInfoProvider, @unchecked Sendable {
    private let cache = NSCache<NSString, Box>()
    private final class Box { let info: AppInfo?; init(_ info: AppInfo?) { self.info = info } }

    public init() {}

    public func appInfo(bundlePath: String) -> AppInfo? {
        if let hit = cache.object(forKey: bundlePath as NSString) { return hit.info }
        let info = Bundle(path: bundlePath).flatMap { bundle -> AppInfo? in
            guard let id = bundle.bundleIdentifier else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? AppGrouper.fallbackName(bundlePath: bundlePath)
            let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            return AppInfo(bundleID: id, name: name, executableName: executable)
        }
        cache.setObject(Box(info), forKey: bundlePath as NSString)
        return info
    }
}

/// Folds processes into app entities (helpers under their app) and standalone process entities.
public struct AppGrouper: Sendable {
    public let selfPID: Int32
    public let currentUID: UInt32
    public let appInfo: any AppInfoProvider

    public init(selfPID: Int32, currentUID: UInt32, appInfo: any AppInfoProvider) {
        self.selfPID = selfPID
        self.currentUID = currentUID
        self.appInfo = appInfo
    }

    public func group(_ samples: [ProcessSample]) -> [Entity] {
        let byPID = Dictionary(samples.map { ($0.process.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var buckets: [EntityKey: (name: String, bundlePath: String?, executableName: String?, members: [ProcessSample])] = [:]
        var order: [EntityKey] = []

        for sample in samples {
            let pid = sample.process.pid
            guard pid != selfPID, pid != 0 else { continue }

            let key: EntityKey
            let name: String
            var executableName: String?
            let bundlePath = appBundlePath(for: sample, byPID: byPID)
            if let bundlePath {
                let info = appInfo.appInfo(bundlePath: bundlePath)
                key = .app(bundleID: info?.bundleID ?? bundlePath)
                name = info?.name ?? Self.fallbackName(bundlePath: bundlePath)
                executableName = info?.executableName
            } else {
                key = .process(path: sample.process.path ?? sample.process.name)
                name = sample.process.name
            }

            if buckets[key] == nil {
                buckets[key] = (name, bundlePath, executableName, [])
                order.append(key)
            }
            buckets[key]?.members.append(sample)
        }

        return order.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            return Entity(
                key: key,
                displayName: bucket.name,
                bundlePath: bucket.bundlePath,
                mainPID: bucket.bundlePath.flatMap {
                    Self.mainPID(in: bucket.members, bundlePath: $0, executableName: bucket.executableName)
                },
                members: bucket.members,
                ownedByCurrentUser: bucket.members.allSatisfy { $0.process.uid == currentUID }
            )
        }
    }

    /// Code inside a `.app` belongs to its own outermost app; the responsible PID is used only for
    /// `.xpc` services outside any app (e.g. WebKit's WebContent → Safari). Trusting it more widely
    /// would blame Terminal for `python3` (Python.app) or `swift-frontend` (Xcode.app), and CLI tools
    /// stay standalone for the same reason.
    func appBundlePath(for sample: ProcessSample, byPID: [Int32: ProcessSample]) -> String? {
        guard let path = sample.process.path else { return nil }
        if let app = Self.appPrefix(in: path) { return app }
        guard Self.offset(of: Self.xpcMarker, in: path) != nil,
              let responsible = sample.process.responsiblePID,
              responsible != sample.process.pid,
              let responsiblePath = byPID[responsible]?.process.path else { return nil }
        return Self.outermostApp(in: responsiblePath)
    }

    public static func outermostApp(in path: String) -> String? {
        appPrefix(in: path) ?? (path.hasSuffix(".app") ? path : nil)
    }

    /// The member whose executable sits directly in `<bundle>/Contents/MacOS/`, preferring `executableName`
    /// when several do; toolchain binaries elsewhere in the bundle (Xcode's `swift-frontend`) are not the app.
    static func mainPID(in members: [ProcessSample], bundlePath: String, executableName: String? = nil) -> Int32? {
        let macOS = bundlePath + "/Contents/MacOS/"
        let direct = members.filter { sample in
            guard let path = sample.process.path, path.hasPrefix(macOS) else { return false }
            return !path.utf8.dropFirst(macOS.utf8.count).contains(UInt8(ascii: "/"))
        }
        if let executableName, let main = direct.first(where: { $0.process.path == macOS + executableName }) {
            return main.process.pid
        }
        return direct.first?.process.pid
    }

    // Grouping runs on every process each tick; Foundation's locale-aware `contains`/`range(of:)`
    // were most of its cost, so paths are matched byte-wise.
    private static let appMarker = Array(".app/".utf8)
    private static let xpcMarker = Array(".xpc/".utf8)

    private static func appPrefix(in path: String) -> String? {
        offset(of: appMarker, in: path).map { String(decoding: path.utf8.prefix($0), as: UTF8.self) + ".app" }
    }

    /// UTF-8 offset of the first `marker` in `path`.
    private static func offset(of marker: [UInt8], in path: String) -> Int? {
        var path = path
        return path.withUTF8 { bytes in
            guard bytes.count >= marker.count else { return nil }
            search: for index in 0...(bytes.count - marker.count) {
                for (shift, byte) in marker.enumerated() where bytes[index + shift] != byte { continue search }
                return index
            }
            return nil
        }
    }

    public static func fallbackName(bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}
