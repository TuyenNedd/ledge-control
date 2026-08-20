import AppKit
import SwiftUI

/// The settings window, hosted via `NSHostingController` wrapping the SwiftUI `SettingsView`.
///
/// Follows the same ownership pattern as `DiagnosticsWindow`: the window is
/// `isReleasedWhenClosed = false` so the menu can reopen it, and `AppDelegate` holds the single
/// instance for the lifetime of the process.
///
/// When Settings opens, the app switches to `.regular` activation policy so it appears in the
/// Dock and gains standard window behaviors (Cmd+W to close). When the window closes, it
/// switches back to `.accessory` to hide from the Dock.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let viewModel: SettingsViewModel

    /// - Parameters:
    ///   - preferences: The shared preferences instance to read from and write to.
    ///   - applyPreferences: Called after any setting changes so the controller re-reads values.
    init(preferences: Preferences, applyPreferences: @escaping () -> Void) {
        let viewModel = SettingsViewModel(preferences: preferences, applyPreferences: applyPreferences)
        self.viewModel = viewModel
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
        // Capture the frontmost app before Settings takes focus, so "Add Current App" knows
        // which app the user was working in.
        viewModel.previousFrontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Show app in the Dock while Settings is open. This gives us standard window behaviors:
        // - Cmd+W to close (comes free with .regular activation policy and .closable style mask)
        // - App icon visible in Dock for easy switching
        // UNVERIFIED: setActivationPolicy(.regular) while already running as .accessory. The
        // transition should be immediate but may have edge cases with window ordering.
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        // Activate to bring the window to front.
        NSApp.activate()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Hide from Dock when Settings closes, returning to menu bar-only mode.
        // UNVERIFIED: setActivationPolicy(.accessory) while a window is closing. There may be
        // a brief flicker of the Dock icon disappearing. Dispatching async may help if needed.
        NSApp.setActivationPolicy(.accessory)
    }
}
