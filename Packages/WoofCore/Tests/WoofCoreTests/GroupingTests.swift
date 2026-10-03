import Foundation
import Testing
@testable import WoofCore

@Suite struct GroupingTests {
    let chrome = "/Applications/Google Chrome.app"
    let terminal = "/System/Applications/Utilities/Terminal.app"
    var grouper: AppGrouper {
        AppGrouper(
            selfPID: 999,
            currentUID: 501,
            appInfo: StubAppInfo(table: [chrome: AppInfo(bundleID: "com.google.Chrome", name: "Google Chrome")])
        )
    }

    @Test func outermostAppIsFoundInHelperPath() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppGrouper.outermostApp(in: path) == chrome)
        #expect(AppGrouper.outermostApp(in: "/usr/bin/yes") == nil)
    }

    @Test func helpersAreSummedIntoTheirApp() {
        let entities = grouper.group([
            sample(1, name: "Google Chrome", path: "\(chrome)/Contents/MacOS/Google Chrome", cpu: 10, memory: gb),
            sample(2, name: "Helper", path: "\(chrome)/Contents/Frameworks/H.app/Contents/MacOS/Helper", cpu: 90, memory: 2 * gb),
        ])
        #expect(entities.count == 1)
        let app = entities[0]
        #expect(app.key == .app(bundleID: "com.google.Chrome"))
        #expect(app.displayName == "Google Chrome")
        #expect(app.cpuPercent == 100)
        #expect(app.memoryBytes == 3 * gb)
        #expect(app.mainPID == 1)
        #expect(app.members.first?.process.pid == 2) // sorted by CPU
    }

    @Test func responsiblePIDGroupsSystemXPCServicesUnderTheApp() {
        let safari = "/Applications/Safari.app"
        let grouper = AppGrouper(
            selfPID: 999, currentUID: 501,
            appInfo: StubAppInfo(table: [safari: AppInfo(bundleID: "com.apple.Safari", name: "Safari")])
        )
        let entities = grouper.group([
            sample(1, name: "Safari", path: "\(safari)/Contents/MacOS/Safari"),
            sample(2, name: "WebContent", path: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", responsible: 1, cpu: 80),
        ])
        #expect(entities.count == 1)
        #expect(entities[0].key == .app(bundleID: "com.apple.Safari"))
        #expect(Set(entities[0].members.map(\.process.pid)) == [1, 2])
        #expect(entities[0].cpuPercent == 80)
    }

    @Test func bundledToolRunFromTerminalGroupsUnderItsOwnBundle() {
        let python = "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app"
        let grouper = AppGrouper(
            selfPID: 999, currentUID: 501,
            appInfo: StubAppInfo(table: [
                python: AppInfo(bundleID: "org.python.python", name: "Python"),
                terminal: AppInfo(bundleID: "com.apple.Terminal", name: "Terminal"),
            ])
        )
        let entities = grouper.group([
            sample(1, name: "Terminal", path: "\(terminal)/Contents/MacOS/Terminal"),
            sample(2, name: "Python", path: "\(python)/Contents/MacOS/Python", responsible: 1, memory: 8 * gb),
        ])
        let pythonEntity = entities.first { $0.key == .app(bundleID: "org.python.python") }
        #expect(pythonEntity?.members.map(\.process.pid) == [2])
        #expect(pythonEntity?.mainPID == 2)
        #expect(entities.first { $0.key == .app(bundleID: "com.apple.Terminal") }?.members.map(\.process.pid) == [1])
    }

    @Test func xcodeToolchainBinaryRunFromTerminalGroupsUnderXcode() {
        let xcode = "/Applications/Xcode.app"
        let grouper = AppGrouper(
            selfPID: 999, currentUID: 501,
            appInfo: StubAppInfo(table: [
                xcode: AppInfo(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
                terminal: AppInfo(bundleID: "com.apple.Terminal", name: "Terminal"),
            ])
        )
        let entities = grouper.group([
            sample(1, name: "Terminal", path: "\(terminal)/Contents/MacOS/Terminal"),
            sample(2, name: "swift-frontend", path: "\(xcode)/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend", responsible: 1, cpu: 300),
        ])
        let xcodeEntity = entities.first { $0.key == .app(bundleID: "com.apple.dt.Xcode") }
        #expect(xcodeEntity?.members.map(\.process.pid) == [2])
        #expect(xcodeEntity?.cpuPercent == 300)
        #expect(entities.first { $0.key == .app(bundleID: "com.apple.Terminal") }?.cpuPercent == 0)
    }

    @Test(arguments: [false, true])
    func mainPIDIsTheBundleExecutableNotAToolchainBinary(toolchainFirst: Bool) {
        let xcode = "/Applications/Xcode.app"
        let main = sample(1, name: "Xcode", path: "\(xcode)/Contents/MacOS/Xcode")
        let tool = sample(2, name: "swift-frontend", path: "\(xcode)/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend", cpu: 300)
        let members = toolchainFirst ? [tool, main] : [main, tool]
        #expect(AppGrouper.mainPID(in: members, bundlePath: xcode) == 1)
    }

    @Test func mainPIDPrefersTheBundleExecutableAmongMacOSMembers() {
        let app = "/Applications/Tool.app"
        let members = [
            sample(1, name: "helper-tool", path: "\(app)/Contents/MacOS/helper-tool"),
            sample(2, name: "Tool", path: "\(app)/Contents/MacOS/Tool"),
        ]
        #expect(AppGrouper.mainPID(in: members, bundlePath: app, executableName: "Tool") == 2)
        #expect(AppGrouper.mainPID(in: members, bundlePath: app, executableName: nil) == 1)
        #expect(AppGrouper.mainPID(in: members, bundlePath: app, executableName: "Missing") == 1)
    }

    @Test func groupUsesTheBundleExecutableForMainPID() {
        let app = "/Applications/Tool.app"
        let grouper = AppGrouper(
            selfPID: 999,
            currentUID: 501,
            appInfo: StubAppInfo(table: [app: AppInfo(bundleID: "com.example.Tool", name: "Tool", executableName: "Tool")])
        )
        let entities = grouper.group([
            sample(1, name: "helper-tool", path: "\(app)/Contents/MacOS/helper-tool"),
            sample(2, name: "Tool", path: "\(app)/Contents/MacOS/Tool"),
        ])
        #expect(entities.first?.mainPID == 2)
    }

    @Test func bundleProviderReadsTheExecutableName() throws {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("woof-\(UUID().uuidString)/Tool.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.Tool", "CFBundleName": "Tool", "CFBundleExecutable": "Tool",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let info = BundleAppInfoProvider().appInfo(bundlePath: app.path)
        #expect(info == AppInfo(bundleID: "com.example.Tool", name: "Tool", executableName: "Tool"))
    }

    @Test func appWithOnlyHelpersHasNoMainPID() {
        let members = [
            sample(2, name: "Helper", path: "\(chrome)/Contents/Frameworks/H.app/Contents/MacOS/Helper"),
            sample(3, name: "crashpad", path: "\(chrome)/Contents/Frameworks/X.framework/Helpers/chrome_crashpad_handler"),
            sample(4, name: "nested", path: "\(chrome)/Contents/MacOS/Sub/tool"),
        ]
        #expect(AppGrouper.mainPID(in: members, bundlePath: chrome) == nil)
    }

    @Test func commandLineToolsStayStandaloneEvenWhenTerminalIsResponsible() {
        let entities = grouper.group([
            sample(1, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            sample(2, name: "node", path: "/opt/homebrew/bin/node", responsible: 1, cpu: 150),
        ])
        let node = entities.first { $0.displayName == "node" }
        #expect(node?.key == .process(path: "/opt/homebrew/bin/node"))
        #expect(node?.isApp == false)
        #expect(node?.cpuPercent == 150)
    }

    @Test func selfAndKernelAreExcluded() {
        let entities = grouper.group([
            sample(0, name: "kernel_task", cpu: 50),
            sample(999, name: "woofWoofCPU", path: "/Applications/woofWoofCPU.app/Contents/MacOS/woofWoofCPU", cpu: 1),
            sample(5, name: "yes", path: "/usr/bin/yes", cpu: 100),
        ])
        #expect(entities.map(\.displayName) == ["yes"])
    }

    @Test func unknownBundleFallsBackToPathAndFolderName() {
        let entities = grouper.group([sample(1, name: "x", path: "/Applications/Odd Thing.app/Contents/MacOS/x")])
        #expect(entities[0].key == .app(bundleID: "/Applications/Odd Thing.app"))
        #expect(entities[0].displayName == "Odd Thing")
    }

    @Test func otherUsersProcessMakesEntityNotOwned() {
        let entities = grouper.group([
            sample(1, name: "a", path: "\(chrome)/Contents/MacOS/Google Chrome"),
            sample(2, name: "b", path: "\(chrome)/Contents/Frameworks/H.app/Contents/MacOS/b", uid: 0),
        ])
        #expect(entities[0].ownedByCurrentUser == false)
    }

    @Test func processWithoutPathIsKeyedByName() {
        let entities = grouper.group([sample(7, name: "mystery", path: nil, cpu: 5)])
        #expect(entities[0].key == .process(path: "mystery"))
    }
}
