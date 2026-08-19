import Sparkle

// UNVERIFIED: SPUStandardUpdaterController requires the host app to be properly bundled with
// an Info.plist containing SUFeedURL. When running via `swift run` (no bundle), Sparkle may
// fail to locate the feed URL. This is expected to work only in the `make app` / .dmg build.

/// Thin wrapper around Sparkle's updater controller.
///
/// Initialized with `startingUpdater: false` so that Sparkle does NOT automatically check
/// for updates on launch. This avoids error popups when there is no appcast.xml published yet
/// or when the user is offline. Manual checks are triggered from the "Check for Updates..."
/// menu item.
final class UpdateController {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Start the updater for background checks. Call this after confirming the appcast is
    /// reachable, or simply let the user trigger manual checks via the menu.
    func startUpdater() {
        try? updaterController.updater.start()
    }

    func checkForUpdates() {
        // UNVERIFIED: `checkForUpdates(_:)` presents a standard Sparkle UI sheet. For a menu
        // bar app with no main window the sheet may not display correctly; if so, consider
        // using SPUUpdater directly with a custom user driver.
        updaterController.checkForUpdates(nil)
    }
}
