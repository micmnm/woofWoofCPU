import AppKit
import SwiftUI
import WoofCore

struct SettingsView: View {
    let settings: SettingsStore
    let forgetUsual: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(settings: settings).tabItem { Label("General", systemImage: "gearshape") }
            DogSettings(settings: settings).tabItem { Label("Dog", systemImage: "pawprint") }
            ExceptionSettings(settings: settings, forgetUsual: forgetUsual).tabItem { Label("Exceptions", systemImage: "eye.slash") }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }
}

struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isRegistered
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?
    @State private var host = WindowRef()
    @State private var optionKey = OptionKeyMonitor()

    /// Slowest first, matching the slider's left-to-right.
    private static let paces: [(seconds: TimeInterval, name: String)] = Array(
        zip(SettingsStore.pollIntervalChoices.reversed(), ["Snoozy", "Laid-back", "Eager", "Zoomies"])
    )

    private var paceValue: Binding<Double> {
        Binding(
            get: { Double(Self.paces.firstIndex { $0.seconds == settings.pollInterval } ?? 0) },
            set: { settings.pollInterval = Self.paces[Int($0.rounded())].seconds }
        )
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                if case .preset(let sensitivity) = settings.limitsSetting { return Double(sensitivity.rawValue) }
                return Double(Sensitivity.balanced.rawValue)
            },
            set: { settings.limitsSetting = .preset(Sensitivity(rawValue: Int($0.rounded())) ?? .balanced) }
        )
    }

    private var sensitivityLabel: String {
        if case .preset(let sensitivity) = settings.limitsSetting { return sensitivity.displayName }
        return "Custom"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Sensitivity: \(sensitivityLabel)").font(.headline)
                    Slider(value: sliderValue, in: 0...4, step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Chill")
                    } maximumValueLabel: {
                        Text("Paranoid")
                    }
                }
                DisclosureGroup("Advanced") {
                    LimitField(title: "CPU above (%)", value: limitBinding(\.cpu.threshold, scale: 1, minShown: 5))
                    LimitField(title: "CPU for (minutes)", value: limitBinding(\.cpu.window, scale: 60, minShown: 0.5))
                    LimitField(title: "Memory above (GB)", value: limitBinding(\.memory.threshold, scale: Self.fractionPerGB, minShown: 0.25, maxStored: 1))
                    LimitField(title: "Memory for (minutes)", value: limitBinding(\.memory.window, scale: 60, minShown: 0.5))
                }
            }
            Section {
                VStack(alignment: .leading) {
                    let pace = Self.paces[Int(paceValue.wrappedValue)]
                    Text("Sniffing: \(pace.name)\(Text(optionKey.isOptionDown ? " · every \(Int(pace.seconds)) s" : "").foregroundStyle(.secondary))")
                        .font(.headline)
                    Slider(value: paceValue, in: 0...Double(Self.paces.count - 1), step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text(Self.paces[0].name)
                    } maximumValueLabel: {
                        Text(Self.paces[Self.paces.count - 1].name)
                    }
                }
                .help("Hold ⌥ to see seconds")
                Stepper("Rows shown in popover: \(settings.rowsShown)", value: $settings.rowsShown, in: SettingsStore.rowsShownRange)
                Toggle("Mute bark", isOn: $settings.soundMuted)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // Syncing the toggle from SMAppService lands here too; only a user change acts.
                        guard enabled != LaunchAtLogin.isRegistered else { return }
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                        syncLaunchAtLogin()
                    }
                if needsApproval || launchError != nil {
                    HStack {
                        Text(launchError ?? "Needs approval in System Settings").foregroundStyle(.secondary)
                        Button("Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { optionKey.start() }
        .onDisappear { optionKey.stop() }
        .background(WindowReader { host.window = $0 })
        // The user may have approved (or removed) the login item in System Settings meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === host.window else { return }
            launchError = nil
            syncLaunchAtLogin()
        }
    }

    private func syncLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isRegistered
        needsApproval = LaunchAtLogin.needsApproval
    }

    /// Memory is stored as a fraction of RAM; one GB (1 << 30, as ByteCountFormatter's memory style) in that unit.
    private static let fractionPerGB = Double(1 << 30) / Double(SystemInfo.physicalMemory)

    /// Displayed value = stored value / scale. Editing switches the slider to Custom.
    /// `minShown` keeps a 0 window (instant bark) or a 0 threshold (everything breaches) out.
    private func limitBinding(
        _ keyPath: WritableKeyPath<Limits, Double>, scale: Double, minShown: Double, maxStored: Double = .infinity
    ) -> Binding<Double> {
        Binding(
            get: { settings.limits[keyPath: keyPath] / scale },
            set: { newValue in
                var limits = settings.limits
                limits[keyPath: keyPath] = min(maxStored, max(minShown, newValue) * scale)
                settings.limitsSetting = .custom(limits)
            }
        )
    }
}

/// Not observed: only read when a key-window notification arrives.
@MainActor
private final class WindowRef {
    weak var window: NSWindow?
}

/// Reports the window hosting this view whenever it changes.
private struct WindowReader: NSViewRepresentable {
    let onChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: (@MainActor (NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange?(window)
        }
    }
}

private struct LimitField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}

struct DogSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let selected = SkinRegistry.skin(id: settings.skinID)
        Form {
            Picker("Skin", selection: $settings.skinID) {
                ForEach(SkinRegistry.all, id: \.id) { skin in
                    Text(skin.displayName).tag(skin.id)
                }
            }
            HStack(spacing: 12) {
                ForEach(DogMood.allCases, id: \.self) { mood in
                    VStack {
                        let portrait = selected.portrait(for: mood)
                        let size = selected.displaySize(of: portrait, fitting: CGSize(width: 56, height: 40))
                        Image(nsImage: portrait)
                            .interpolation(selected.isPixelArt ? .none : .high)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .frame(width: 54, height: 40)
                        Text(mood.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ExceptionSettings: View {
    let settings: SettingsStore
    let forgetUsual: () -> Void
    @State private var optionKey = OptionKeyMonitor()
    @State private var confirmingForget = false

    var body: some View {
        Form {
            Section("Bigger bowls") {
                if settings.bowls.isEmpty {
                    Text("Every app eats from the regular bowl. Pick a bigger one from an app's ⋯ menu.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.bowls.keys.sorted(by: { label($0) < label($1) }), id: \.self) { key in
                    Picker(label(key), selection: Binding(
                        get: { settings.bowl(for: key) },
                        set: { settings.setBowl($0, for: key) }
                    )) {
                        ForEach(Bowl.allCases, id: \.self) { bowl in
                            Text(Formatting.bowl(bowl, shared: settings.limits, technical: optionKey.isOptionDown)).tag(bowl)
                        }
                    }
                }
            }
            .help("Hold ⌥ to see memory limits")
            Section("Always ignored") {
                if settings.ignoreList.isEmpty {
                    Text("Nothing ignored yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(settings.ignoreList).sorted(by: { label($0) < label($1) }), id: \.self) { key in
                    HStack {
                        Text(label(key))
                        Spacer()
                        Button("Remove") { settings.removeFromIgnoreList(key) }
                    }
                }
            }
            Section("Snoozed") {
                if settings.snoozes.isEmpty {
                    Text("No snoozes.").foregroundStyle(.secondary)
                }
                ForEach(settings.snoozes.sorted(by: { $0.value < $1.value }), id: \.key) { key, until in
                    HStack {
                        Text(label(key))
                        Spacer()
                        Text("until \(until.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                        Button("Cancel") { settings.cancelSnooze(key) }
                    }
                }
            }
            Section {
                Button("Forget what's usual…") { confirmingForget = true }
                    .confirmationDialog("Forget what's usual for every app?", isPresented: $confirmingForget) {
                        Button("Forget", role: .destructive, action: forgetUsual)
                    } message: {
                        Text("The dog relearns each app's usual usage over the next few hours.")
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { optionKey.start() }
        .onDisappear { optionKey.stop() }
    }

    private func label(_ key: EntityKey) -> String {
        switch key {
        case .app(let bundleID): bundleID
        case .process(let path): path
        }
    }
}
