import Foundation

public struct AppInfo: Equatable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public protocol AppInfoProvider: Sendable {
    func appInfo(bundlePath: String) -> AppInfo?
}

/// Reads `CFBundleIdentifier` / display name from the bundle's Info.plist, cached per path.
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
            return AppInfo(bundleID: id, name: name)
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
        var buckets: [EntityKey: (name: String, bundlePath: String?, members: [ProcessSample])] = [:]
        var order: [EntityKey] = []

        for sample in samples {
            let pid = sample.process.pid
            guard pid != selfPID, pid != 0 else { continue }

            let key: EntityKey
            let name: String
            let bundlePath = appBundlePath(for: sample, byPID: byPID)
            if let bundlePath {
                let info = appInfo.appInfo(bundlePath: bundlePath)
                key = .app(bundleID: info?.bundleID ?? bundlePath)
                name = info?.name ?? Self.fallbackName(bundlePath: bundlePath)
            } else {
                key = .process(path: sample.process.path ?? sample.process.name)
                name = sample.process.name
            }

            if buckets[key] == nil {
                buckets[key] = (name, bundlePath, [])
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
                mainPID: bucket.bundlePath.flatMap { Self.mainPID(in: bucket.members, bundlePath: $0) },
                members: bucket.members,
                ownedByCurrentUser: bucket.members.allSatisfy { $0.process.uid == currentUID }
            )
        }
    }

    /// Only bundled code (inside a `.app` or `.xpc`) is grouped; plain CLI tools stay standalone,
    /// otherwise a runaway `node` started from Terminal would be blamed on Terminal.
    func appBundlePath(for sample: ProcessSample, byPID: [Int32: ProcessSample]) -> String? {
        guard let path = sample.process.path,
              path.contains(".app/") || path.contains(".xpc/") else { return nil }
        if let responsible = sample.process.responsiblePID,
           responsible != sample.process.pid,
           let responsiblePath = byPID[responsible]?.process.path,
           let app = Self.outermostApp(in: responsiblePath) {
            return app
        }
        return Self.outermostApp(in: path)
    }

    public static func outermostApp(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// The member whose executable sits directly in the app (exactly one `.app/` in its path).
    static func mainPID(in members: [ProcessSample], bundlePath: String) -> Int32? {
        members.first { sample in
            guard let path = sample.process.path, path.hasPrefix(bundlePath + "/") else { return false }
            return path.components(separatedBy: ".app/").count == 2
        }?.process.pid
    }

    public static func fallbackName(bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}
