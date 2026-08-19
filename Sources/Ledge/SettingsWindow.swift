import AppKit
import SwiftUI

/// The settings window, hosted via `NSHostingController` wrapping the SwiftUI `SettingsView`.
///
/// Follows the same ownership pattern as `DiagnosticsWindow`: the window is
/// `isReleasedWhenClosed = false` so the menu can reopen it, and `AppDelegate` holds the single
/// instance for the lifetime of the process.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow

    /// - Parameters:
    ///   - preferences: The shared preferences instance to read from and write to.
    ///   - applyPreferences: Called after any setting changes so the controller re-reads values.
    init(preferences: Preferences, applyPreferences: @escaping () -> Void) {
        let viewModel = SettingsViewModel(preferences: preferences, applyPreferences: applyPreferences)
        let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))

        let contentFrame = NSRect(x: 0, y: 0, width: 780, height: 580)
        window = NSWindow(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        // Hide the title text but keep the traffic lights (close button)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentViewController = hostingController
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        // Required because the app is `.accessory`: without this the window can appear behind
        // whatever the user was looking at.
        NSApp.activate()
    }
}
