import AppKit

/// Assembles the object graph and starts the tap.
///
/// Ownership is worth being explicit about, because two things depend on it. The touch source
/// hands an *unretained* pointer to itself to the event tap, and `GestureController` holds the
/// single `GestureEngine`; both rely on this delegate outliving them, which it does because
/// `main.swift` holds it in a global for the life of the process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let touchSource = EventTapTouchSource()

    // Built in `applicationDidFinishLaunching`, not at init, so that nothing touches AppKit
    // before the app is running.
    private var controller: GestureController?
    private var menuBar: MenuBarController?
    private var diagnostics: DiagnosticsWindow?
    private var settingsWindow: SettingsWindow?
    private var onboardingWindow: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = GestureController(preferences: preferences, touchSource: touchSource)
        self.controller = controller

        let diagnostics = DiagnosticsWindow(controller: controller)
        self.diagnostics = diagnostics

        let settingsWindow = SettingsWindow(preferences: preferences) { [weak controller] in
            controller?.applyPreferences()
        }
        self.settingsWindow = settingsWindow

        let menuBar = MenuBarController(preferences: preferences, controller: controller)
        menuBar.onShowDiagnostics = { diagnostics.show() }
        menuBar.onShowSettings = { settingsWindow.show() }
        self.menuBar = menuBar

        // Prompts if needed. Granting does not take effect until relaunch, so the alert below is
        // still the right response to a failed start even when the user says yes immediately.
        Permissions.requestIfNeeded()

        // Show the onboarding flow on first launch. The onboarding window polls AXIsProcessTrusted
        // itself and provides step-count feedback by reading from the controller.
        if !preferences.hasCompletedOnboarding {
            let onboarding = OnboardingWindow(
                preferences: preferences,
                stepCountProvider: { [weak controller] in controller?.stepCount ?? 0 }
            )
            self.onboardingWindow = onboarding
            onboarding.show()
        }

        if !controller.start() {
            presentPermissionAlert(diagnostics: diagnostics)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    /// The tap could not be created, which in practice means one thing.
    ///
    /// Offers the diagnostics window as well as System Settings, because the readout states
    /// whether the process is trusted — which is how a user tells "I have not granted it" from
    /// "I granted it and it still is not working."
    private func presentPermissionAlert(diagnostics: DiagnosticsWindow) {
        let alert = NSAlert()
        alert.messageText = "Ledge needs Accessibility permission."
        alert.informativeText = """
            Ledge reads trackpad touches through an event tap, which macOS only allows for apps \
            trusted in Privacy & Security → Accessibility.

            Grant permission there, then quit and relaunch Ledge — a newly granted tap does not \
            take effect until the app restarts.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Show Diagnostics")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openAccessibilitySettings()
        case .alertSecondButtonReturn:
            diagnostics.show()
        default:
            break
        }
    }

    private func openAccessibilitySettings() {
        // UNVERIFIED: this URL scheme is the long-standing one for the Accessibility pane, but the
        // pane identifiers were reorganised in the System Settings rewrite and may have moved
        // again in macOS 26. Worst case it opens System Settings at the wrong place, which is a
        // small annoyance rather than a failure — the alert text says where to go.
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
