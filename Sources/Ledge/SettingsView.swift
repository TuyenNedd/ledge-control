import SwiftUI
import ServiceManagement
import LedgeCore

/// The root SwiftUI view for the Settings window, using a sidebar with grouped sections.
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
        .frame(width: 780, height: 580)
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

            Toggle("Enable Ledge", isOn: Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.isEnabled = $0 }
            ))
            Text("Master switch - disables all gesture detection when off.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)

            Toggle("Launch at Login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.launchAtLogin = $0 }
            ))
                .padding(.top, 8)
            Text("Start Ledge automatically when you log in.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)
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
/// Slider values write to `Preferences` immediately (so the trackpad preview updates in
/// real-time), but the heavier `applyPreferences()` call is deferred to when the slider
/// drag ends via `applyIfNeeded()`. Toggle changes apply immediately since they are
/// discrete events.
// UNVERIFIED: @Observable macro on a class with explicit didSet calling side effects.
@Observable
final class SettingsViewModel {
    private let preferences: Preferences
    private let applyPreferencesClosure: () -> Void

    /// Whether a slider is currently being dragged. When true, `didSet` writes to preferences
    /// but does not call `applyPreferences()`.
    var isEditingSlider: Bool = false

    // MARK: - Gesture settings

    var edgeBandWidth: Double {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var activationDistance: Double {
        didSet { writeGestureSettings(); applyIfNotEditing() }
    }

    var fineControl: Bool {
        didSet { writeGestureSettings(); applyPreferencesClosure() }
    }

    var swapSides: Bool {
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
        self.edgeBandWidth = settings.edgeBandWidth
        self.activationDistance = settings.activationDistance
        self.fineControl = settings.fineControl
        self.swapSides = settings.swapSides
        self.bottomQuarterOnly = settings.bottomQuarterOnly
        self.typingLockout = settings.typingLockout
        self.gestureTimeout = settings.gestureTimeout

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

    /// Applies preferences only when not in the middle of a slider drag.
    private func applyIfNotEditing() {
        if !isEditingSlider {
            applyPreferencesClosure()
        }
    }

    private func writeGestureSettings() {
        var settings = preferences.gestureSettings
        settings.edgeBandWidth = edgeBandWidth
        settings.activationDistance = activationDistance
        settings.fineControl = fineControl
        settings.swapSides = swapSides
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
