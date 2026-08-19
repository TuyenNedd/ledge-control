import Sparkle

// UNVERIFIED: SPUStandardUpdaterController requires the host app to be properly bundled with
// an Info.plist containing SUFeedURL. When running via `swift run` (no bundle), Sparkle may
// fail to locate the feed URL. This is expected to work only in the `make app` / .dmg build.

/// Thin wrapper around Sparkle's updater controller.
///
/// Initialized at launch with `startingUpdater: true` so that automatic background checks
/// begin immediately. Manual checks are triggered from the menu bar.
final class UpdateController {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        // UNVERIFIED: `checkForUpdates(_:)` presents a standard Sparkle UI sheet. For a menu
        // bar app with no main window the sheet may not display correctly; if so, consider
        // using SPUUpdater directly with a custom user driver.
        updaterController.checkForUpdates(nil)
    }
}
