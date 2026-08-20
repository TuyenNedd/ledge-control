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
final class SettingsWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let window: NSWindow
    private let viewModel: SettingsViewModel

    /// - Parameters:
    ///   - preferences: The shared preferences instance to read from and write to.
    ///   - applyPreferences: Called after any setting changes so the controller re-reads values.
    init(preferences: Preferences, applyPreferences: @escaping () -> Void) {
        let viewModel = SettingsViewModel(preferences: preferences, applyPreferences: applyPreferences)
        self.viewModel = viewModel
        let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))

        let contentFrame = NSRect(x: 0, y: 0, width: 900, height: 650)
        window = NSWindow(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
        window.toolbarStyle = .unified

        // Install an empty toolbar whose delegate returns no allowed items.
        // This prevents SwiftUI's NavigationSplitView from injecting the
        // sidebar toggle button.
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar

        window.contentViewController = hostingController
    }

    func show() {
        // Capture the frontmost app before Settings takes focus, so "Add Current App" knows
        // which app the user was working in.
        viewModel.previousFrontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Show app in the Dock while Settings is open.
        NSApp.setActivationPolicy(.regular)

        // Set up a main menu so ⌘W and traffic light buttons work.
        // Without a menu bar, .regular activation policy still won't deliver ⌘W.
        setupMainMenu()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Lock the sidebar open so macOS has no reason to show the toggle button.
        DispatchQueue.main.async { [weak self] in
            guard let self, let contentView = self.window.contentView else { return }
            if let splitView = self.findSplitView(in: contentView),
               let splitViewController = splitView.delegate as? NSSplitViewController,
               let sidebarItem = splitViewController.splitViewItems.first {
                sidebarItem.isCollapsed = false
                sidebarItem.canCollapse = false
            }
        }
    }

    private func findSplitView(in view: NSView) -> NSSplitView? {
        if let splitView = view as? NSSplitView {
            return splitView
        }
        for subview in view.subviews {
            if let found = findSplitView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    /// Creates a minimal main menu bar with File > Close (⌘W) so standard keyboard shortcuts
    /// and traffic light buttons work when the app is in .regular activation policy.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (required for the menu bar to appear)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Ledge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu with Close
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Hide from Dock when Settings closes, returning to menu bar-only mode.
        NSApp.setActivationPolicy(.accessory)
        // Remove the main menu so it doesn't linger after the window is gone.
        NSApp.mainMenu = nil
    }
}
