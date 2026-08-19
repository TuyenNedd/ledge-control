# Ledge

Slide along the edge of your MacBook trackpad to change volume and brightness.

Right edge for volume, left edge for brightness, fine granularity, one full-height slide spans
the whole range. Lives in the menu bar. No configuration required.

---

## Download

Grab the latest `.dmg` from [GitHub Releases](https://github.com/TuyenNedd/ledge-control/releases).
Open the disk image, drag Ledge.app to Applications, and follow the first-run instructions inside.

---

## First launch

On first launch, an onboarding flow guides you through granting Accessibility permission. The
Settings window (⌘,) is available afterward for tuning preferences. If you ever need to re-grant
permission, the onboarding will appear again automatically.

---

## Features (Phase 2b)

- **Modifier key requirement** -- optionally require holding Option, Fn, or Control before a
  trackpad edge gesture activates. Eliminates accidental triggers during normal trackpad use.
- **Per-app disable list** -- disable Ledge gestures in specific applications (e.g., drawing apps
  or games that use the full trackpad surface).
- **Auto-update via Sparkle** -- the app checks for updates on launch and can be triggered
  manually from the menu. See [`docs/SPARKLE.md`](docs/SPARKLE.md) for setup details.
- **Export/import settings** -- save all preferences as a JSON file for backup or sharing across
  machines, and import them back from the Settings window.

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

---

## For developers

**Development (persistent Accessibility permission across rebuilds):**

```bash
make cert           # one-time: create an Apple Development certificate (free via Xcode, see docs/CERTIFICATE.md)
make reinstall      # quit, rebuild, install to /Applications, and relaunch
```

The stable certificate means the Accessibility grant survives rebuilds without needing
`make reset-permission` after every change.

**Distribution (ad-hoc signed `.dmg` for sharing):**

```bash
make dmg            # builds with ad-hoc signing and packages dist/Ledge-<version>.dmg
```

The `.dmg` includes a symlink to `/Applications` for drag-to-install and a `FIRST-RUN.txt`
explaining how to bypass Gatekeeper on first launch.

---

### Why a bundle and not just a binary

Accessibility permission is granted to a *bundle identity*, not to a file. `Resources/Info.plist`
pins `CFBundleIdentifier` to `xyz.tuyennedd.ledge` and never changes it, which is the minimum
required for the app to be able to hold the grant at all.

### Expect to re-grant permission (ad-hoc signing only)

If you skip the certificate setup and use ad-hoc signing (`make app`), the Accessibility grant
resets on every rebuild because macOS matches the binary's hash. The symptom is the app keeping
its enabled checkbox in **Privacy & Security > Accessibility** while the grant does nothing.

```bash
make reset-permission   # tccutil reset Accessibility xyz.tuyennedd.ledge
```

Quit the app, run that, relaunch, grant again. To avoid this, sign with an Apple Development
certificate (free via Xcode) as described in [`docs/CERTIFICATE.md`](docs/CERTIFICATE.md).

---

## Menu

The menu bar icon provides:

- **Enabled** -- master toggle
- **Swap Sides** -- flip volume/brightness edges
- **Fine Control** -- smaller step size per gesture increment
- **Bottom Quarter Only** -- restrict activation to the bottom quarter of the trackpad
- **Freeze Cursor** -- hold the pointer still during a gesture
- **Continuous Volume** -- use CoreAudio backend for stepless volume (no HUD)
- **Launch at Login** -- start Ledge automatically on login
- ---
- **Settings...** (⌘,) -- opens the Settings window for all preferences
- **Check for Updates...** -- manually check for a newer version via Sparkle
- **Diagnostics...** -- live readout of touch data, engine state, volume, brightness
- **Quit Ledge**

Toggles are available in both the menu bar and the Settings window.

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
- **The Accessibility grant does not survive a rebuild with ad-hoc signing.** If you skip the
  certificate setup (see "For developers" above), the app looks enabled in Privacy & Security
  while the grant has no effect. Use `make reset-permission` after each build, or set up the
  Apple Development certificate to avoid this entirely.
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
- **Sparkle auto-update requires additional setup to be fully functional.** The update mechanism
  needs GitHub Pages hosting for the appcast feed and Ed25519 signing keys. See
  [`docs/SPARKLE.md`](docs/SPARKLE.md) for the complete setup procedure.

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
