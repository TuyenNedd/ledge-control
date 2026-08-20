import SwiftUI
import ServiceManagement
import LedgeCore
import UniformTypeIdentifiers

/// The root SwiftUI view for the Settings window, using a sidebar with grouped sections.
///
/// The sidebar toggle button is removed via `.navigationSplitViewStyle(.balanced)` to provide
/// a cleaner appearance without the collapsible sidebar affordance.
struct SettingsView: View {
    var viewModel: SettingsViewModel

    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, Hashable {
        case general = "General"
        case gesture = "Gesture"
        case behavior = "Behavior"
        case about = "About"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsTab.general)

                Section("Features") {
                    Label("Gesture", systemImage: "hand.draw")
                        .tag(SettingsTab.gesture)
                    Label("Behavior", systemImage: "slider.horizontal.3")
                        .tag(SettingsTab.behavior)
                }

                Section("System") {
                    Label("About", systemImage: "info.circle")
                        .tag(SettingsTab.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab(viewModel: viewModel)
                case .gesture:
                    GestureSettingsTab(viewModel: viewModel)
                case .behavior:
                    BehaviorSettingsTab(viewModel: viewModel)
                case .about:
                    AboutTab()
                }
            }
        }
        // Remove the sidebar toggle button. .balanced alone may not remove it on macOS 26;
        // .toolbar(removing:) is the explicit approach.
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(width: 900, height: 650)
    }
}

/// General tab - enable/disable and launch at login.
/// Redesigned to match DockDoor-style layout with section headers and descriptions.
struct GeneralSettingsTab: View {
    var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Application section
            Text("APPLICATION")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            SettingsToggleRow(
                title: "Enable Ledge",
                description: "Master switch - disables all gesture detection when off.",
                isOn: Binding(
                    get: { viewModel.isEnabled },
                    set: { viewModel.isEnabled = $0 }
                )
            )

            SettingsToggleRow(
                title: "Launch at Login",
                description: "Start Ledge automatically when you log in.",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.launchAtLogin = $0 }
                )
            )
            .padding(.top, 8)

            // MARK: - Settings Data section
            Text("SETTINGS DATA")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 24)

            HStack(spacing: 12) {
                Button("Export Settings") {
                    viewModel.exportSettings()
                }
                Button("Import Settings") {
                    viewModel.importSettings()
                }
            }
            Text("Export or import all Ledge settings as a JSON file.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// View model that bridges `Preferences` to SwiftUI bindings.
///
/// Uses `@Observable` (macOS 14+) so that views can read properties directly without
/// explicit `@Published` wrappers.
///
/// Per-edge `EdgeConfig` properties replace the old `edgeBandWidth` and `swapSides`.
/// Each edge config change writes to preferences immediately and propagates through
/// the interactive trackpad preview in real time.
///
/// All Toggle controls render as switches on macOS 14+ by default (the system style for
/// Toggle on macOS 14+ is a switch when used outside of a Form).
// UNVERIFIED: @Observable macro on a class with explicit didSet calling side effects.
@Observable
final class SettingsViewModel {
    private let preferences: Preferences
    private let applyPreferencesClosure: () -> Void

    /// Whether a slider is currently being dragged. When true, `didSet` writes to preferences
    /// but does not call `applyPreferences()`.
    var isEditingSlider: Bool = false

    // MARK: - Per-Edge Configuration

    var leftEdge: EdgeConfig {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var rightEdge: EdgeConfig {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var topEdge: EdgeConfig {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var bottomEdge: EdgeConfig {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    // MARK: - Gesture settings

    var activationDistance: Double {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var fineControl: Bool {
        didSet { writeGestureSettings(); applyPreferencesClosure() }
    }

    var bottomQuarterOnly: Bool {
        didSet { writeGestureSettings(); applyPreferencesClosure() }
    }

    // MARK: - Behavior settings

    var isEnabled: Bool {
        didSet { preferences.isEnabled = isEnabled; applyPreferencesClosure() }
    }

    var cursorFreezeEnabled: Bool {
        didSet { preferences.cursorFreezeEnabled = cursorFreezeEnabled; applyPreferencesClosure() }
    }

    var useCoreAudioVolume: Bool {
        didSet { preferences.useCoreAudioVolume = useCoreAudioVolume; applyPreferencesClosure() }
    }

    var modifierKeyRequired: ModifierKeyMode {
        didSet { preferences.modifierKeyRequired = modifierKeyRequired; applyPreferencesClosure() }
    }

    var excludedApps: [String] {
        didSet { preferences.excludedApps = excludedApps; applyPreferencesClosure() }
    }

    /// The bundle ID of the app that was frontmost before Settings opened. Set by the caller
    /// when the settings window appears, so "Add Current App" has something to offer.
    var previousFrontmostApp: String?

    var typingLockout: Double {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var gestureTimeout: Double {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }

    init(preferences: Preferences, applyPreferences: @escaping () -> Void) {
        self.preferences = preferences
        self.applyPreferencesClosure = applyPreferences

        let settings = preferences.gestureSettings

        // Per-edge configuration
        self.leftEdge = settings.leftEdge
        self.rightEdge = settings.rightEdge
        self.topEdge = settings.topEdge
        self.bottomEdge = settings.bottomEdge

        // Shared gesture settings
        self.activationDistance = settings.activationDistance
        self.fineControl = settings.fineControl
        self.bottomQuarterOnly = settings.bottomQuarterOnly
        self.typingLockout = settings.typingLockout
        self.gestureTimeout = settings.gestureTimeout

        // Adapter-layer settings
        self.isEnabled = preferences.isEnabled
        self.cursorFreezeEnabled = preferences.cursorFreezeEnabled
        self.useCoreAudioVolume = preferences.useCoreAudioVolume
        self.modifierKeyRequired = preferences.modifierKeyRequired
        self.excludedApps = preferences.excludedApps

        // UNVERIFIED: SMAppService.mainApp.status == .enabled for reading login item state.
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Called when a slider drag ends to apply the final value to the gesture engine.
    func sliderEditingChanged(_ editing: Bool) {
        isEditingSlider = editing
        if !editing {
            applyPreferencesClosure()
        }
    }

    /// Add a bundle identifier to the exclusion list. No-op if already present.
    func addExcludedApp(_ bundleID: String) {
        guard !excludedApps.contains(bundleID) else { return }
        excludedApps.append(bundleID)
    }

    /// Remove a bundle identifier from the exclusion list.
    func removeExcludedApp(_ bundleID: String) {
        excludedApps.removeAll { $0 == bundleID }
    }

    /// Export all settings to a JSON file via NSSavePanel.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ledge-settings.json"
        panel.title = "Export Settings"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = SettingsIO.exportSettings(from: preferences)
        try? data.write(to: url)
    }

    /// Import settings from a JSON file via NSOpenPanel, then refresh.
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Settings"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        SettingsIO.importSettings(from: data, into: preferences)
        // Refresh all view model properties from the updated preferences.
        reloadFromPreferences()
        applyPreferencesClosure()
    }

    /// Re-read all properties from preferences. Called after import to sync the UI.
    private func reloadFromPreferences() {
        let settings = preferences.gestureSettings

        // Per-edge configuration
        leftEdge = settings.leftEdge
        rightEdge = settings.rightEdge
        topEdge = settings.topEdge
        bottomEdge = settings.bottomEdge

        // Shared gesture settings
        activationDistance = settings.activationDistance
        fineControl = settings.fineControl
        bottomQuarterOnly = settings.bottomQuarterOnly
        typingLockout = settings.typingLockout
        gestureTimeout = settings.gestureTimeout

        // Adapter-layer settings
        isEnabled = preferences.isEnabled
        cursorFreezeEnabled = preferences.cursorFreezeEnabled
        useCoreAudioVolume = preferences.useCoreAudioVolume
        modifierKeyRequired = preferences.modifierKeyRequired
        excludedApps = preferences.excludedApps
    }

    /// Applies preferences only when not in the middle of a slider drag.
    private func applyIfNotEditing() {
        if !isEditingSlider {
            applyPreferencesClosure()
        }
    }

    private func writeGestureSettings() {
        var settings = preferences.gestureSettings

        // Per-edge configuration
        settings.leftEdge = leftEdge
        settings.rightEdge = rightEdge
        settings.topEdge = topEdge
        settings.bottomEdge = bottomEdge

        // Shared gesture settings
        settings.activationDistance = activationDistance
        settings.fineControl = fineControl
        settings.bottomQuarterOnly = bottomQuarterOnly
        settings.typingLockout = typingLockout
        settings.gestureTimeout = gestureTimeout

        preferences.gestureSettings = settings
    }

    private func updateLaunchAtLogin() {
        // UNVERIFIED: SMAppService.mainApp register/unregister for bundled, signed app.
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the UI state on failure.
            launchAtLogin = !launchAtLogin
        }
    }
}
