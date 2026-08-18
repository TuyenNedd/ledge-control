import AppKit
import ServiceManagement

/// The status item and its menu — the app's entire user interface, apart from diagnostics.
///
/// Every item does the same two things: write one preference, then tell `GestureController` to
/// re-read all of them. Nothing here interprets a preference or decides what it means; the
/// meaning lives in `GestureSettings` and `Preferences`.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let preferences: Preferences
    private let controller: GestureController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    /// Set by `AppDelegate`, which owns the window.
    var onShowDiagnostics: (() -> Void)?

    /// Set by `AppDelegate`, which owns the settings window.
    var onShowSettings: (() -> Void)?

    /// Each toggle paired with how to read its current value, so `menuNeedsUpdate(_:)` can refresh
    /// checkmarks in one loop instead of needing a stored property per item.
    ///
    /// The closures capture `Preferences` rather than `self`, so this array is not a retain cycle.
    private var toggles: [(item: NSMenuItem, isOn: () -> Bool)] = []

    init(preferences: Preferences, controller: GestureController) {
        self.preferences = preferences
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // UNVERIFIED: that "slider.vertical.3" is present on macOS 26. It has existed since
            // SF Symbols 1, so this is close to certain — but `systemSymbolName:` returns nil for
            // an unknown name, which would leave an invisible status item, so the title fallback
            // below guarantees something clickable either way.
            let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Ledge")
            image?.isTemplate = true
            button.image = image
            if image == nil {
                button.title = "Ledge"
            }
        }

        menu.delegate = self
        buildMenu()
        statusItem.menu = menu

        controller.onEngagementChanged = { [weak self] engaged in
            if engaged {
                self?.statusItem.button?.contentTintColor = .controlAccentColor
            } else {
                self?.statusItem.button?.contentTintColor = nil
            }
        }
    }

    private func buildMenu() {
        // Captured locally so the state closures do not reference `self`.
        let preferences = self.preferences

        addToggle("Enabled", action: #selector(toggleEnabled)) { preferences.isEnabled }

        menu.addItem(.separator())

        addToggle("Swap Sides", action: #selector(toggleSwapSides)) { preferences.gestureSettings.swapSides }
        addToggle("Fine Control", action: #selector(toggleFineControl)) { preferences.gestureSettings.fineControl }
        addToggle("Bottom Quarter Only", action: #selector(toggleBottomQuarterOnly)) {
            preferences.gestureSettings.bottomQuarterOnly
        }

        menu.addItem(.separator())

        addToggle("Freeze Cursor During Gesture", action: #selector(toggleCursorFreeze)) {
            preferences.cursorFreezeEnabled
        }
        // Named for the trade-off rather than for the implementation, because the trade-off is the
        // only reason a user would ever choose it.
        addToggle("Continuous Volume (No HUD)", action: #selector(toggleCoreAudioVolume)) {
            preferences.useCoreAudioVolume
        }

        menu.addItem(.separator())

        addToggle("Launch at Login", action: #selector(toggleLaunchAtLogin)) {
            MenuBarController.isLaunchAtLoginEnabled
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let diagnostics = NSMenuItem(title: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)

        let quit = NSMenuItem(title: "Quit Ledge", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addToggle(_ title: String, action: Selector, isOn: @escaping () -> Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        // `NSMenuItem.target` is a weak reference, so this does not create a cycle with the menu
        // that `statusItem` retains.
        item.target = self
        menu.addItem(item)
        toggles.append((item, isOn))
    }

    /// Checkmarks are refreshed when the menu opens rather than when a preference changes, so a
    /// value edited elsewhere — `defaults write`, or Login Items in System Settings — cannot leave
    /// the menu lying about it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for toggle in toggles {
            toggle.item.state = toggle.isOn() ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
        controller.applyPreferences()
    }

    @objc private func toggleSwapSides() {
        var settings = preferences.gestureSettings
        settings.swapSides.toggle()
        preferences.gestureSettings = settings
        controller.applyPreferences()
    }

    @objc private func toggleFineControl() {
        var settings = preferences.gestureSettings
        settings.fineControl.toggle()
        preferences.gestureSettings = settings
        controller.applyPreferences()
    }

    @objc private func toggleBottomQuarterOnly() {
        var settings = preferences.gestureSettings
        settings.bottomQuarterOnly.toggle()
        preferences.gestureSettings = settings
        controller.applyPreferences()
    }

    @objc private func toggleCursorFreeze() {
        preferences.cursorFreezeEnabled.toggle()
        controller.applyPreferences()
    }

    @objc private func toggleCoreAudioVolume() {
        preferences.useCoreAudioVolume.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        // UNVERIFIED: `SMAppService.mainApp` only works for a properly bundled, signed app that
        // the system can locate — an ad-hoc signature is expected to be enough, but a `swift run`
        // binary with no bundle certainly is not, and registration is reported to be unreliable
        // for apps outside /Applications. It throws rather than failing silently, and the error is
        // surfaced, so a failure here is at least legible. Use `make install` before testing this.
        do {
            if MenuBarController.isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item."
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func showDiagnostics() {
        onShowDiagnostics?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
