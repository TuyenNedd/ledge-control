import AppKit

// A SwiftPM executable takes its entry point from top-level code in a file named `main.swift`,
// which is why there is no `@main` type anywhere in this target.

let application = NSApplication.shared

// A global, so it lives for the whole process: `NSApplication.delegate` is a weak reference, and
// everything the app owns — the event tap, the gesture engine — hangs off this object.
let delegate = AppDelegate()
application.delegate = delegate

// No Dock icon, no app menu. `Info.plist`'s `LSUIElement` says the same thing for a bundled
// launch; this covers `swift run`, where there is no bundle and therefore no plist to read.
_ = application.setActivationPolicy(.accessory)

application.run()
