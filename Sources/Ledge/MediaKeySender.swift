import AppKit

/// The `NX_KEYTYPE_*` constants for the media keys this app synthesises.
///
/// Raw values are the hardware key codes carried in the high half of a system-defined event's
/// `data1`. They are listed here rather than imported from `<IOKit/hidsystem/ev_keymap.h>`
/// because that header is not modularised for Swift, so the constants cannot be imported —
/// only re-declared.
///
/// `brightnessUp`/`brightnessDown` are included for completeness and for the diagnostics
/// window's benefit, but **nothing in the app posts them**: `docs/DESIGN.md` records that
/// synthesised brightness keys do not change brightness on this machine, which is the whole
/// reason `BrightnessController` exists. Do not wire them up without re-testing that finding.
enum MediaKey: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
}

/// Posts a media key press as if the hardware key had been struck.
///
/// This is the *only* remaining route to a native volume HUD on macOS 26: `OSDUIHelper` is gone
/// (see `docs/DESIGN.md`), so the HUD cannot be summoned, only earned — by letting the OS make
/// the change itself. Everything in this type exists to make the event indistinguishable from a
/// real key so that happens.
enum MediaKeySender {
    /// The `NX_SUBTYPE_AUX_CONTROL_BUTTONS` subtype that marks a system-defined event as a
    /// media key rather than one of the other things that share `.systemDefined`.
    private static let auxControlButtonsSubtype: Int16 = 8

    /// The state bits ORed into the low half of `data1`.
    private static let keyDownState = 0x0A00
    private static let keyUpState = 0x0B00

    /// Post one complete press: key down immediately followed by key up.
    ///
    /// Both halves are sent because the OS advances volume on the *down* transition but will
    /// treat a key it never saw released as held, which starts its auto-repeat. One step per
    /// call is the contract `GestureEvent.step` expects.
    ///
    /// - Parameter fine: When true the event carries `.shift` + `.option`, which is how the
    ///   hardware keys ask for quarter-steps. See the note on `flags(fine:)` — this is the
    ///   single least certain thing in the volume path.
    static func post(_ key: MediaKey, fine: Bool) {
        send(key, isDown: true, fine: fine)
        send(key, isDown: false, fine: fine)
    }

    private static func send(_ key: MediaKey, isDown: Bool, fine: Bool) {
        let data1 = (key.rawValue << 16) | (isDown ? keyDownState : keyUpState)

        // `.systemDefined` is one of the types Apple documents as permitted for
        // `NSEvent.otherEvent(with:)`, and a disallowed type raises an exception rather than
        // returning nil — so this is not the suspicious step. The `guard` stays because the
        // signature is optional, not because nil is expected.
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags(fine: fine),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: auxControlButtonsSubtype,
            data1: data1,
            data2: -1
        ) else { return }

        // Why this cannot feed back into our own event tap.
        //
        // Not because of where it is posted. `.cghidEventTap` injects *below* the session level,
        // which means a session tap — like `EventTapTouchSource`'s — sees the event afterwards, on
        // its way up. Posting here is the least private route, not a way of hiding.
        //
        // The actual protection is the shape of the tap callback. What we post is a
        // `.systemDefined` event, and `EventTapTouchSource.handle(type:event:)` has no case for
        // that type: it falls to `default:`, which returns the event untouched and never reaches
        // the `GestureEngine`. So a synthesised media key cannot produce a touch frame, cannot
        // produce a step, and cannot cause another post.
        //
        // This used to be assured by `.systemDefined` simply not being in the tap's event mask.
        // It is now — the mask subscribes to every type — so if a case for `.systemDefined` is
        // ever added to that switch, this loop becomes real. Anything added there must ignore
        // events it recognises as our own.
        //
        // UNVERIFIED: that `event.cgEvent` is non-nil for a `.systemDefined` event built this way.
        // The bridge back to CoreGraphics is the step with no documented guarantee, and it is
        // where to look first if volume never moves at all.
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    /// The modifiers that ask the OS for a quarter-step instead of a whole step.
    ///
    /// UNVERIFIED — and this is the known risk called out in `docs/DESIGN.md`: pressing
    /// `Shift`+`Option`+volume on the hardware keyboard gives 64 sub-steps, but whether
    /// WindowServer honours those flags when they arrive on a *synthesised* event is untested.
    /// It may simply ignore them, in which case fine mode silently degrades to the usual 16
    /// coarse steps — steps get 4x bigger, nothing breaks, and the app is still useful.
    ///
    /// How to tell: on-device checklist item 3. Open Diagnostics, slide the right edge, and
    /// watch the volume scalar. ~1.6% per step means the flags are honoured; ~6.25% means they
    /// are not, `fineControl` is a lie in the menu, and it should be removed rather than left
    /// there implying something it does not do.
    private static func flags(fine: Bool) -> NSEvent.ModifierFlags {
        fine ? [.shift, .option] : []
    }
}
