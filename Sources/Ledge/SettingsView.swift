import SwiftUI
import ServiceManagement

/// The root SwiftUI view for the Settings window, using a sidebar navigation style.
// UNVERIFIED: NavigationSplitView on macOS 14+ for settings sidebar.
struct SettingsView: View {
    var viewModel: SettingsViewModel

    @State private var selectedTab: SettingsTab = .gesture

    enum SettingsTab: String, CaseIterable {
        case gesture = "Gesture"
        case behavior = "Behavior"
        case about = "About"

        var icon: String {
            switch self {
            case .gesture: return "hand.draw"
            case .behavior: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 180)
        } detail: {
            switch selectedTab {
            case .gesture:
                GestureSettingsTab(viewModel: viewModel)
            case .behavior:
                BehaviorSettingsTab(viewModel: viewModel)
            case .about:
                AboutTab()
            }
        }
        .frame(width: 580, height: 400)
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
