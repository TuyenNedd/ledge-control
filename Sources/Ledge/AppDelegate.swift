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
            // First launch: onboarding handles everything. Do NOT call Permissions.isTrusted()
            // or requestIfNeeded() here — on macOS 26, even a check-only call to
            // AXIsProcessTrustedWithOptions can trigger the system "Accessibility Access" dialog
            // the first time it sees this app, and that dialog appearing ON TOP of our onboarding
            // window is confusing. The onboarding permission page has its own "Open System
            // Settings" button and polls only AFTER a 3-second delay to let its window appear first.
            let onboarding = OnboardingWindow(
                preferences: preferences,
                stepCountProvider: { [weak controller] in controller?.stepCount ?? 0 },
                touchPositionProvider: { [weak controller] in
                    guard let pos = controller?.lastFrame?.touches.first?.position else { return nil }
                    return (x: pos.x, y: pos.y)
                },
                isEngagedProvider: { [weak controller] in controller?.engagedControl != nil },
                volumeProvider: { [weak controller] in controller?.currentVolumeScalar() },
                brightnessProvider: { [weak controller] in controller?.currentBrightness() }
            )
            self.onboardingWindow = onboarding
            onboarding.show()

            // Poll for permission in the background. Once granted, start the tap and relaunch
            // so the onboarding "Try It" page can work.
            startPollingForPermission()
        } else {
            // Not first launch. Try to start silently — if permission exists, great.
            // If not, just poll in the background and auto-start/relaunch when granted.
            // No alert shown — the user already went through onboarding and knows what to do.
            if Permissions.isTrusted() {
                _ = controller.start()
            } else {
                startPollingForPermission()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Poll AXIsProcessTrusted every 2 seconds. When permission is granted, start the tap
    /// (or relaunch if needed). Delays the first check by 3 seconds so the onboarding window
    /// has time to appear before any system prompt that the first isTrusted() call may trigger.
    private func startPollingForPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if Permissions.isTrusted() {
                    timer.invalidate()
                    if let controller = self?.controller, controller.start() {
                        // Tap started — bring the onboarding window back to front so the user
                        // sees the status change and can proceed to "Try It"
                        self?.onboardingWindow?.show()
                    } else {
                        self?.relaunch()
                    }
                }
            }
        }
    }

    /// Quit and immediately relaunch the app.
    private func relaunch() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}
