import SwiftUI
import ServiceManagement

/// The root SwiftUI view for the Settings window, containing three tabs.
// UNVERIFIED: TabView with .automatic tabViewStyle on macOS 14+.
struct SettingsView: View {
    var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            GestureSettingsTab(viewModel: viewModel)
                .tabItem { Label("Gesture", systemImage: "hand.draw") }

            BehaviorSettingsTab(viewModel: viewModel)
                .tabItem { Label("Behavior", systemImage: "gearshape") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        // UNVERIFIED: .automatic style is the default for macOS TabView but being explicit.
        .frame(width: 460, height: 360)
    }
}

/// View model that bridges `Preferences` to SwiftUI bindings.
///
/// Uses `@Observable` (macOS 14+) so that views can read properties directly without
/// explicit `@Published` wrappers.
// UNVERIFIED: @Observable macro on a class with explicit didSet calling side effects.
@Observable
final class SettingsViewModel {
    private let preferences: Preferences
    private let applyPreferencesClosure: () -> Void

    // MARK: - Gesture settings

    var edgeBandWidth: Double {
        didSet { writeGestureSettings(); applyPreferencesClosure() }
    }

    var activationDistance: Double {
        didSet { writeGestureSettings(); applyPreferencesClosure() }
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
        didSet { writeGestureSettings(); applyPreferencesClosure() }
    }

    var gestureTimeout: Double {
        didSet { writeGestureSettings(); applyPreferencesClosure() }
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
