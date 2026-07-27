import ApplicationServices
import Foundation

/// The Accessibility trust check that gates the event tap.
///
/// Without trust, `CGEvent.tapCreate` returns nil and the app is inert — so this is the first
/// thing `AppDelegate` asks about and the first line of the diagnostics window.
///
/// Trust is granted to a **bundle identity**, not to a path, which is why `Resources/Info.plist`
/// pins `CFBundleIdentifier` and the `Makefile` never generates one. A changing identifier means
/// re-granting permission after every rebuild.
enum Permissions {
    /// Whether the process is already trusted. Never prompts.
    static func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    /// Whether the process is trusted, asking the system to show the "open Privacy & Security"
    /// prompt if it is not.
    ///
    /// The prompt is asynchronous and granting it does not retroactively make this return true —
    /// macOS also requires the app to be relaunched before a newly granted tap works. The return
    /// value therefore describes the state *now*, and a false means "tell the user to grant and
    /// relaunch", not "wait a moment".
    @discardableResult
    static func requestIfNeeded() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is an `Unmanaged<CFString>` in Swift. It is bridged
        // through `String` rather than used as a `CFString` key directly because `[String: Bool]`
        // has a guaranteed, unsurprising conversion to `CFDictionary`.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
