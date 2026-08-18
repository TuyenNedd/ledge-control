# Ledge

Slide along the edge of your MacBook trackpad to change volume and brightness.

Right edge for volume, left edge for brightness, fine granularity, one full-height slide spans
the whole range. Lives in the menu bar. No configuration required.

---

## How it works

Two layers, split by what can be tested.

**`LedgeCore`** is pure Swift with zero imports. It holds every decision the app makes and builds
and tests anywhere, including Linux. `GestureEngine` turns a stream of `TouchFrame`s into
`GestureEvent`s and is where all the guards against accidental activation live.

**`Sources/Ledge/`** is a macOS-only shell of thin adapters -- a `CGEvent` tap for input,
synthesised media keys for volume, `DisplayServices` for brightness, AppKit for the menu.
It deliberately contains no branching logic worth testing.

### Volume

`MediaKeySender` posts synthesised `NX_KEYTYPE_SOUND_UP` / `NX_KEYTYPE_SOUND_DOWN` events with
`.shift`+`.option` modifier flags for fine mode. The OS performs the change itself and draws its
own HUD indicator. Zero private API involved.

`CoreAudioVolumeController` exists as a selectable fallback for genuinely continuous control,
but it produces no HUD.

### Brightness

`DisplayServicesBrightnessController` resolves symbols from
`/System/Library/PrivateFrameworks/DisplayServices.framework` at runtime via `dlopen`/`dlsym`.
It sets the brightness value directly, then posts a synthesised brightness media key event. The
media key does not change the brightness (that is already done), but it does trigger the native
HUD indicator to display the current level.

Loading by `dlsym` rather than linking means a missing symbol on a future macOS degrades to
"brightness disabled, volume still works" instead of a launch failure.

### Cursor freeze

When enabled, the pointer holds still during a gesture. Each `mouseMoved` event during an active
gesture warps the cursor back to the saved position using `CGWarpMouseCursorPosition` and
swallows the event. On disengage the cursor resumes normal movement.

Two other approaches were tried and failed:
- **Returning nil for mouseMoved events** -- never actually prevented cursor movement.
- **`CGAssociateMouseAndMouseCursorPosition(false)`** -- does not work on macOS 26.

### Two OS findings that shaped this

**`OSDUIHelper` no longer exists on macOS 26 Tahoe.** The XPC route that MonitorControl and
SlimHUD use to summon the native volume/brightness HUD is gone -- confirmed by Apple DTS in
[developer forums thread 804054](https://developer.apple.com/forums/thread/804054). So the HUD
cannot be requested directly.

**Synthesised brightness media keys do not change brightness, but they do trigger the native
indicator.** Volume keys both change the value and show the HUD. Brightness keys only show the
HUD without changing anything
([thread 60545](https://developer.apple.com/forums/thread/60545)). So the brightness approach
is: `DisplayServices` performs the actual change, then a synthesised media key triggers the
native HUD display.

Full reasoning, including the rejected alternatives, is in [`docs/DESIGN.md`](docs/DESIGN.md).

---

## Build

Requires macOS 14+ (developed and verified on macOS 26.2 Tahoe, Apple Silicon) and Xcode.
No paid Apple Developer account needed.

```bash
make app        # build and assemble dist/Ledge.app, ad-hoc signed
make install    # copy to /Applications
```

Then launch it from `/Applications`, grant Accessibility permission when asked, and **relaunch**.

`make run` launches the bundle. Do not use `swift run` -- a bare binary has no bundle identity, so
it can never hold the Accessibility permission the app depends on.

Other targets: `make build`, `make test`, `make reset-permission`, `make clean`.

### Why a bundle and not just a binary

Accessibility permission is granted to a *bundle identity*, not to a file. `Resources/Info.plist`
pins `CFBundleIdentifier` to `xyz.tuyennedd.ledge` and never changes it, which is the minimum
required for the app to be able to hold the grant at all.

### Expect to re-grant permission after every rebuild

A fixed bundle identifier is not enough. macOS matches the *designated requirement* of the
signature, and for the ad-hoc signature `make app` applies that requirement is derived from the
binary's hash -- so a rebuilt app is, as far as permissions are concerned, a different program.

The symptom is worse than a refusal: the app keeps its enabled checkbox in **Privacy & Security >
Accessibility** while the grant does nothing, and `CGEvent.tapCreate` returns nil. That is
indistinguishable from the event tap simply not working, so rule it out first:

```bash
make reset-permission   # tccutil reset Accessibility xyz.tuyennedd.ledge
```

Quit the app, run that, relaunch, grant again. To avoid it entirely without a paid Developer
account, sign with a stable self-signed code-signing certificate from Keychain Access instead of
ad-hoc -- an unchanging certificate gives an unchanging designated requirement. See the Makefile
header.

---

## Menu

The menu bar icon provides:

- **Enabled** -- master toggle
- **Swap Sides** -- swap volume/brightness edges
- **Fine Control** -- 1/64 steps (on) vs 1/16 steps (off)
- **Bottom Quarter Only** -- restrict gesture activation to the bottom quarter of the trackpad
- **Freeze Cursor During Gesture** -- hold the pointer still while sliding
- **Launch at Login** -- via SMAppService
- **Diagnostics** -- live readout of touch data, engine state, volume, brightness
- **Quit**

---

## Tuning

Every threshold lives in `Sources/LedgeCore/GestureSettings.swift`, each with a doc comment
explaining what it trades off in both directions. Nothing about *when* a gesture fires exists
anywhere else.

Current tuned values:
- `edgeBandWidth`: `0.025` (~4mm) -- narrow band for precise edge targeting
- `maxDriftOutsideBand`: `0.02` -- tight tolerance before an engaged gesture is abandoned

If you get false positives, in order of bluntness:

1. Lower `edgeBandWidth` -- smaller target, fewer accidental entries
2. Raise `activationDistance` -- a longer deliberate movement required
3. Raise `typingLockout` -- longer suppression after a keystroke
4. Enable **Bottom Quarter Only** from the menu -- the strongest defence, and the most restrictive

The relational tests in `GestureSettingsTests.swift` allow a fair amount of retuning before they
complain, and they will tell you if you push two settings into a combination that contradicts
itself.

---

## Known gaps

- **Two-finger scroll ending in one finger can produce a false positive.** When a second finger
  lifts, the remaining finger is re-evaluated from wherever it now is, so it can arm without ever
  having "started" in the edge band. This is the most likely false positive in day-one use.
  Fixing it properly means remembering rejected touch ids as a set.
- **A full-height slide covers ~62.5 steps, not 64,** so 0% to 100% is not quite reachable in one
  stroke. `stepDistance` is `0.016`, an approximation of `1/64`.
- **External displays are out of scope.** Built-in only; no DDC.
- **The Accessibility grant does not survive a rebuild** while the app is ad-hoc signed, and the
  app looks enabled while it is not. `make reset-permission` after each build, or sign with a
  stable self-signed certificate. See "Expect to re-grant permission after every rebuild" above.
- **The event tap subscribes to every event type**, because per-type subscription is reported not
  to be honoured for gesture events. That means the tap callback runs for every event in the
  session. It does nothing but count and return for types it ignores, but if the tap starts being
  disabled by timeout under load, the narrow mask is kept commented in
  `EventTapTouchSource.swift` as the thing to try.
- **Touch ids are only assumed unique among fingers currently down.** After a finger lifts, the OS
  could in principle give a later finger the same id. Nothing exploits that today -- a rejected or
  engaged id is only consulted while it keeps appearing in frames -- but it is why the diagnostics
  window prints raw ids.
- **The CoreAudio backend clears mute on the way up only.** Sliding down on a muted device leaves
  it muted, deliberately. The media-key backend gets mute handling from the OS.

---

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) -- architecture, rejected alternatives, risk table
- [`docs/plans/2026-07-27-trackpad-edge-gestures.md`](docs/plans/2026-07-27-trackpad-edge-gestures.md)
  -- implementation plan and post-implementation notes

## Prior art

This is a from-scratch reimplementation of an idea sold commercially as
[Slidr](https://slidr.xyz) ($4.99). No Slidr code was seen or used -- it is closed source. Its
changelog was, however, genuinely instructive: v1.0 shipped the gesture, and bottom-quarter mode,
typing detection, cursor freeze and modifier keys all arrived across v1.1-v1.3. Those are not
features, they are false-positive fixes found in daily use, and shipping them in v1 here is the
most valuable thing this project borrowed.

## License

MIT -- see [LICENSE](LICENSE).
