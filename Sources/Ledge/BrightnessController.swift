import CoreGraphics
import Darwin
import Foundation
import LedgeCore

/// Drives the built-in display's backlight through `DisplayServices`.
///
/// This is a private framework, and using it is a considered cost rather than a shortcut. The
/// public routes were tried first and do not work on this machine (`docs/DESIGN.md`):
/// synthesised `NX_KEYTYPE_BRIGHTNESS_UP`/`DOWN` events do nothing, and
/// `IODisplaySetFloatParameter` does not reach the internal panel on Apple Silicon. This is
/// what is left.
///
/// **Symbols are resolved with `dlsym`, never by linking.** Linking would make a missing symbol
/// on some future macOS a launch failure for the whole app; resolving at runtime makes it cost
/// exactly one feature. `isAvailable` reports which world we are in, and the diagnostics window
/// shows it, so "brightness stopped working" is a five-second diagnosis rather than a mystery.
final class BrightnessController {
    /// `int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness)`
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    /// `int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness)`
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    /// `int DisplayServicesBrightnessChanged(CGDirectDisplayID display, double brightness)`
    ///
    /// Note the `double` where the other two take `float` — that asymmetry is in the framework,
    /// not a transcription slip. Getting it wrong would corrupt the argument silently.
    private typealias BrightnessChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let getBrightness: GetBrightnessFn?
    private let setBrightness: SetBrightnessFn?
    private let brightnessChanged: BrightnessChangedFn?

    /// The display this controller drives, resolved once at init.
    ///
    /// Resolved once rather than per call because this app is built for a machine with no
    /// external display (`docs/DESIGN.md` non-goals). If external display support is ever added,
    /// this becomes a lookup and that is where the change belongs.
    private let display: CGDirectDisplayID

    /// Whether the private symbols resolved. When false, `adjust` does nothing and the menu and
    /// diagnostics window both say so — volume keeps working.
    var isAvailable: Bool {
        getBrightness != nil && setBrightness != nil
    }

    init() {
        // RTLD_LAZY, and the handle is intentionally never `dlclose`d: the function pointers
        // below outlive this initialiser and must stay mapped for the life of the process.
        // Spelled with the full type name rather than `Self`, because these run before the stored
        // properties are initialised and there is no reason to make the compiler think about it.
        let handle = dlopen(BrightnessController.frameworkPath, RTLD_LAZY)

        func resolve<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }

        getBrightness = resolve("DisplayServicesGetBrightness", as: GetBrightnessFn.self)
        setBrightness = resolve("DisplayServicesSetBrightness", as: SetBrightnessFn.self)
        // Optional even when the other two resolve. Without it the brightness still changes;
        // only the system's own indicator is lost.
        brightnessChanged = resolve("DisplayServicesBrightnessChanged", as: BrightnessChangedFn.self)

        display = BrightnessController.builtInDisplay()
    }

    /// Move brightness one step.
    ///
    /// Read-modify-write rather than a relative call, because `DisplayServices` offers no
    /// relative one. The step size comes from `SystemStepFraction` so brightness and the
    /// CoreAudio volume backend agree on what a step is worth.
    func adjust(_ direction: StepDirection, fine: Bool) {
        guard let setBrightness, let current = currentBrightness() else { return }

        let delta = SystemStepFraction.delta(fine: fine)
        // Translating the engine's direction into a sign — not a decision about when to move.
        let signed = direction == .up ? delta : -delta
        let target = min(max(current + signed, 0), 1)

        guard setBrightness(display, target) == 0 else { return }

        // UNVERIFIED: whether this still makes the OS draw its own brightness indicator on
        // macOS 26. It is the call MonitorControl and friends use for exactly that, but the same
        // Tahoe housecleaning that removed `OSDUIHelper` may have left it inert. On-device
        // checklist item 4 decides whether a custom overlay is needed. Either way brightness
        // itself changes, so a silent no-op here is cosmetic, not fatal.
        _ = brightnessChanged?(display, Double(target))
    }

    /// Current brightness, 0...1, or nil if it cannot be read. Also used by diagnostics.
    func currentBrightness() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return value
    }

    /// The internal panel, falling back to the main display.
    ///
    /// The fallback is not a guess about which display the user means — with no external display
    /// attached the main display *is* the built-in one. It exists so that a failure of
    /// `CGGetActiveDisplayList` leaves brightness working rather than dead.
    private static func builtInDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return CGMainDisplayID()
        }
        for display in displays.prefix(Int(count)) where CGDisplayIsBuiltin(display) != 0 {
            return display
        }
        return CGMainDisplayID()
    }
}
