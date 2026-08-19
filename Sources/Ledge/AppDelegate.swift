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

        if !preferences.hasCompletedOnboarding {
            // First launch: onboarding handles everything — permission explanation, granting,
            // and auto-relaunch. Do NOT call Permissions.requestIfNeeded() here (that triggers
            // the system prompt on top of the onboarding window) and do NOT show our own alert.
            // The onboarding permission page polls AXIsProcessTrusted and guides the user.
            let onboarding = OnboardingWindow(
                preferences: preferences,
                stepCountProvider: { [weak controller] in controller?.stepCount ?? 0 }
            )
            self.onboardingWindow = onboarding
            onboarding.show()

            // Still try to start — if permission was pre-granted (e.g. re-running onboarding
            // after a defaults delete), the tap works and page 3 can detect gestures.
            _ = controller.start()
        } else {
            // Not first launch: prompt for permission if needed and start the tap.
            Permissions.requestIfNeeded()
            let startSucceeded = controller.start()

            if !startSucceeded {
                presentPermissionAlert()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    /// The tap could not be created, which in practice means one thing.
    ///
    /// Offers to open System Settings, and once permission is granted the app relaunches itself
    /// automatically. Also offers a manual "Relaunch Now" button for users who grant permission
    /// in their own time.
    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Ledge needs Accessibility permission."
        alert.informativeText = """
            Ledge reads trackpad touches through an event tap, which macOS only allows for apps \
            trusted in Privacy & Security → Accessibility.

            Grant permission there — the app will relaunch automatically once it detects the change.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openAccessibilitySettings()
            startPollingForPermission()
        case .alertSecondButtonReturn:
            relaunch()
        default:
            // "Later" — still poll in the background so it relaunches when granted
            startPollingForPermission()
        }
    }

    /// Poll AXIsProcessTrusted every 2 seconds. When permission is granted, relaunch
    /// automatically so the event tap can be created.
    private func startPollingForPermission() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if Permissions.isTrusted() {
                timer.invalidate()
                self?.relaunch()
            }
        }
    }

    /// Quit and immediately relaunch the app.
    private func relaunch() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        // Give the new instance a moment to start before we terminate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
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
