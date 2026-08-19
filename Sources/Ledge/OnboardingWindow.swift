import AppKit
import SwiftUI

/// The first-launch onboarding window, hosted via `NSHostingController` wrapping `OnboardingView`.
///
/// Follows the same ownership pattern as `SettingsWindow` and `DiagnosticsWindow`: the window is
/// `isReleasedWhenClosed = false` so the instance can be safely retained by `AppDelegate`, and
/// the window is never resizable because the layout is fixed across three pages.
///
/// Uses an `OnboardingCoordinator` to wire the close action post-init, avoiding the previous
/// pattern of replacing `hostingController.rootView` (which caused double view-tree construction).
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow

    /// - Parameters:
    ///   - preferences: Shared preferences instance (for setting `hasCompletedOnboarding`).
    ///   - stepCountProvider: Closure that returns the current step count from the gesture controller.
    ///   - touchPositionProvider: Closure that returns the current finger position (x, y) in 0...1 normalized space, or nil if no touch.
    ///   - isEngagedProvider: Closure that returns whether a gesture is currently engaged.
    ///   - volumeProvider: Closure that returns the current volume scalar (0...1), or nil if unavailable.
    ///   - brightnessProvider: Closure that returns the current brightness scalar (0...1), or nil if unavailable.
    init(
        preferences: Preferences,
        stepCountProvider: @escaping () -> Int,
        touchPositionProvider: @escaping () -> (x: Double, y: Double)? = { nil },
        isEngagedProvider: @escaping () -> Bool = { false },
        volumeProvider: @escaping () -> Float? = { nil },
        brightnessProvider: @escaping () -> Float? = { nil }
    ) {
        // UNVERIFIED: NSHostingController with SwiftUI view as root content for macOS 14+.
        let coordinator = OnboardingCoordinator()
        let onboardingView = OnboardingView(
            preferences: preferences,
            stepCountProvider: stepCountProvider,
            touchPositionProvider: touchPositionProvider,
            isEngagedProvider: isEngagedProvider,
            volumeProvider: volumeProvider,
            brightnessProvider: brightnessProvider,
            coordinator: coordinator
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

        // Wire the close action after window creation via the coordinator, no need to replace
        // the rootView.
        coordinator.closeAction = { [weak window] in
            window?.close()
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        // For a .accessory (LSUIElement) app, makeKeyAndOrderFront alone is not enough —
        // the window can appear behind whatever the user was looking at. Both of these
        // are needed: activate brings the app to the front, orderFrontRegardless ensures
        // this specific window is above everything else regardless of app activation state.
        window.orderFrontRegardless()
        NSApp.activate()
    }
}
