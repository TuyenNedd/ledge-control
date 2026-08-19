import SwiftUI
import ServiceManagement

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
        .frame(width: 680, height: 500)
    }
}

/// General tab — launch at login, enable/disable.
struct GeneralSettingsTab: View {
    var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GENERAL")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            Toggle("Enable Ledge", isOn: Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.isEnabled = $0 }
            ))

            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.launchAtLogin = $0 }
            ))
        }
        .padding(.horizontal, 24)
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
