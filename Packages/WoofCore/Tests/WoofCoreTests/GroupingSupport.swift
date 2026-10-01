@testable import WoofCore

func entity(_ name: String, cpu: Double = 0, memory: UInt64 = 0, uid: UInt32 = 501) -> Entity {
    Entity(
        key: .process(path: "/usr/bin/\(name)"),
        displayName: name,
        bundlePath: nil,
        mainPID: nil,
        members: [sample(100, name: name, path: "/usr/bin/\(name)", uid: uid, cpu: cpu, memory: memory)],
        ownedByCurrentUser: uid == 501
    )
}

struct StubAppInfo: AppInfoProvider {
    var table: [String: AppInfo] = [:]
    func appInfo(bundlePath: String) -> AppInfo? { table[bundlePath] }
}
