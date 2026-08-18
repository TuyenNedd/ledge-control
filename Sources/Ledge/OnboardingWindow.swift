import AppKit
import SwiftUI

/// The first-launch onboarding window, hosted via `NSHostingController` wrapping `OnboardingView`.
///
/// Follows the same ownership pattern as `SettingsWindow` and `DiagnosticsWindow`: the window is
/// `isReleasedWhenClosed = false` so the instance can be safely retained by `AppDelegate`, and
/// the window is never resizable because the layout is fixed across three pages.
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow

    /// - Parameters:
    ///   - preferences: Shared preferences instance (for setting `hasCompletedOnboarding`).
    ///   - stepCountProvider: Closure that returns the current step count from the gesture controller.
    init(preferences: Preferences, stepCountProvider: @escaping () -> Int) {
        // UNVERIFIED: NSHostingController with SwiftUI view as root content for macOS 14+.
        let onboardingView = OnboardingView(
            preferences: preferences,
            stepCountProvider: stepCountProvider,
            closeWindow: {}
        )
        let hostingController = NSHostingController(rootView: onboardingView)

        let contentFrame = NSRect(x: 0, y: 0, width: 550, height: 450)
        window = NSWindow(
            contentRect: contentFrame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Welcome to Ledge"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentViewController = hostingController

        // Wire closeWindow after initialization so the closure can reference `window`.
        // UNVERIFIED: mutating the rootView after assignment to contentViewController.
        let windowRef = window
        hostingController.rootView = OnboardingView(
            preferences: preferences,
            stepCountProvider: stepCountProvider,
            closeWindow: { [weak windowRef] in
                windowRef?.close()
            }
        )
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        // Required because the app is `.accessory`: without this the window can appear behind
        // whatever the user was looking at.
        NSApp.activate()
    }
}
