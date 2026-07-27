# Ledge

Slide along the edge of your MacBook trackpad to change volume and brightness.

Right edge for volume, left edge for brightness, one haptic pulse per step. Lives in the menu
bar. No configuration.

---

## ⚠️ Read this before you build

**The macOS half of this app has never been compiled.**

It was written in a Linux sandbox with no macOS, no AppKit, no Xcode, and no Apple hardware.

| Layer | Status |
|---|---|
| `Sources/LedgeCore/` — all gesture logic | **Built and tested.** 54 unit tests passing, verified by running them |
| `Sources/Ledge/` — event tap, system APIs, menu bar | **Written, never executed.** ~1,500 lines that have not been through a compiler |

Expect the first `make app` to produce compile errors. They should be small — wrong argument
labels, deprecations — but they will be there. Search the source for `// UNVERIFIED:` to find
every assumption that was made without being able to check it; there are thirteen, and the
load-bearing ones are in `EventTapTouchSource.swift`.

The single question that decides whether any of this works is on-device checklist item 1 below:
does a `CGEvent` tap actually deliver single-finger trackpad touches? Everything else is
downstream of that answer.

---

## Build

Requires macOS 14+ (developed for macOS 26.2 on Apple Silicon) and Xcode. No paid Apple
Developer account needed.

```bash
make app        # build and assemble dist/Ledge.app, ad-hoc signed
make install    # copy to /Applications
```

Then launch it from `/Applications`, grant Accessibility permission when asked, and **relaunch**.

`make run` launches the bundle. Do not use `swift run` — a bare binary has no bundle identity, so
it can never hold the Accessibility permission the app depends on.

Other targets: `make build`, `make test`, `make reset-permission`, `make clean`.

### Why a bundle and not just a binary

Accessibility permission is granted to a *bundle identity*, not to a file. `Resources/Info.plist`
pins `CFBundleIdentifier` to `xyz.tuyennedd.ledge` and never changes it, which is the minimum
required for the app to be able to hold the grant at all.

### Expect to re-grant permission after every rebuild

A fixed bundle identifier is not enough. macOS matches the *designated requirement* of the
signature, and for the ad-hoc signature `make app` applies that requirement is derived from the
binary's hash — so a rebuilt app is, as far as permissions are concerned, a different program.

The symptom is worse than a refusal: the app keeps its enabled checkbox in **Privacy & Security >
Accessibility** while the grant does nothing, and `CGEvent.tapCreate` returns nil. That is
indistinguishable from the event tap simply not working, so rule it out first:

```bash
make reset-permission   # tccutil reset Accessibility xyz.tuyennedd.ledge
```

Quit the app, run that, relaunch, grant again. To avoid it entirely without a paid Developer
account, sign with a stable self-signed code-signing certificate from Keychain Access instead of
ad-hoc — an unchanging certificate gives an unchanging designated requirement. See the Makefile
header.

---

## First run: verify it actually works

Open **Diagnostics** from the menu bar icon. That window exists specifically because this layer
was written blind — it turns each unverifiable assumption into something you can read at a glance.

Work down this list in order. If step 1 fails, nothing below it matters.

- [ ] **1. Does the event tap deliver touches?** Move the pointer, then rest one finger on the
      trackpad, and read *Events seen (all types)*, *Gesture frames seen* and *Touch count*
      together. The tap subscribes to every event type precisely so these three tell three
      different failures apart:
      - All three climbing → the core assumption holds, carry on.
      - **Events seen 0** → the tap delivers nothing whatsoever. This is permission or
        `tapCreate`, not gestures. Quit, `make reset-permission`, relaunch, grant again — and only
        then suspect anything else.
      - **Events climbing, gesture frames 0** → the tap works but type 29 never arrives. The
        public event tap route is dead and the private `MultitouchSupport.framework` is the only
        remaining option. `TouchSource` is the seam that substitution happens at.
      - **Gesture frames climbing, touch count 0** → gesture events arrive without touch data
        attached. Same conclusion as above.
- [ ] **2. Are touch ids stable?** With one finger held down, *Raw touch ids* must not change.
      `LedgeCore` matches fingers between frames by `NSTouch.identity.hash`; if that hash changes
      per frame, every frame looks like a new finger and both arming and stepping break silently.
- [ ] **2b. Does lifting a finger empty the frame?** Lift your finger and watch *Touch count* fall
      back to 0. An empty frame is how `LedgeCore` learns the gesture ended; if the count sticks
      at 1, the phase filter in `EventTapTouchSource.emitFrame` is not working, gestures only end
      on the stale-gesture timeout, and cursor freeze strands the pointer in the meantime.
- [ ] **3. Volume responds.** Slide the right edge. Volume should change *and* the system HUD
      should appear.
- [ ] **4. Is fine control real?** Watch *Volume scalar* while stepping.
      - Steps of ~1.6% → `Shift`+`Option` is honoured on synthesised events, fine mode works.
      - Steps of ~6.25% → the flags are ignored. Fine mode is a no-op and the menu item is
        lying; remove it rather than leave it there.
- [ ] **5. Brightness responds.** Slide the left edge. Note whether any system indicator appears —
      that decides whether a custom HUD is needed. If *DisplayServices* reads `NOT RESOLVED`, the
      private symbols are gone and brightness cannot work at all.
- [ ] **6. Haptics** fire once per step and don't feel noisy.
- [ ] **7. Cursor freeze** holds the pointer still during a gesture, and leaves no stuck input
      afterwards.
- [ ] **8. False positives.** Use the machine normally for a day — scroll, type, drag. Count
      unintended changes. This is the real test; see Tuning.
- [ ] **9. Permission after a rebuild.** Rebuild, relaunch, and confirm the app still works.
      Expect it not to, with an ad-hoc signature: run `make reset-permission` and grant again. If
      re-granting is needed every time, a stable self-signed certificate is the fix.

---

## Tuning

Every threshold lives in `Sources/LedgeCore/GestureSettings.swift`, each with a doc comment
explaining what it trades off in both directions. Nothing about *when* a gesture fires exists
anywhere else.

If you get false positives, in order of bluntness:

1. Lower `edgeBandWidth` — smaller target, fewer accidental entries
2. Raise `activationDistance` — a longer deliberate movement required
3. Raise `typingLockout` — longer suppression after a keystroke
4. Enable **Bottom quarter only** from the menu — the strongest defence, and the most restrictive

The relational tests in `GestureSettingsTests.swift` allow a fair amount of retuning before they
complain, and they will tell you if you push two settings into a combination that contradicts
itself.

---

## How it works

Two layers, split by what can be tested.

**`LedgeCore`** is pure Swift with zero imports. It holds every decision the app makes and builds
and tests anywhere, including Linux. `GestureEngine` turns a stream of `TouchFrame`s into
`GestureEvent`s and is where all the guards against accidental activation live.

**`Sources/Ledge/`** is a macOS-only shell of thin adapters — a `CGEvent` tap for input,
synthesised media keys for volume, `DisplayServices` for brightness, AppKit for the menu.
It deliberately contains no branching logic worth testing, which is the only reason it is
acceptable for it to be untested.

### Two OS findings that shaped this

**`OSDUIHelper` no longer exists on macOS 26 Tahoe.** The XPC route that MonitorControl and
SlimHUD use to summon the native volume/brightness HUD is gone — confirmed by Apple DTS in
[developer forums thread 804054](https://developer.apple.com/forums/thread/804054). So the HUD
cannot be requested directly.

Volume therefore goes through **synthesised media keys**: the OS performs the change itself, so it
draws its own indicator for free, with no private API involved. CoreAudio is offered as an
alternative backend — genuinely continuous, but no HUD, so not the default.

**Synthesised brightness media keys don't work,** while the volume equivalents do
([thread 60545](https://developer.apple.com/forums/thread/60545)). Brightness therefore needs the
private `DisplayServices` framework, resolved via `dlsym` rather than linked so that a symbol
vanishing in a future macOS costs one feature instead of the whole app launching.

Full reasoning, including the rejected alternatives, is in [`docs/DESIGN.md`](docs/DESIGN.md).

---

## Known gaps

- **Two-finger scroll ending in one finger can produce a false positive.** When a second finger
  lifts, the remaining finger is re-evaluated from wherever it now is, so it can arm without ever
  having "started" in the edge band. This is the most likely false positive in day-one use.
  Fixing it properly means remembering rejected touch ids as a set.
- **A full-height slide covers ~62.5 steps, not 64,** so 0% to 100% isn't quite reachable in one
  stroke. `stepDistance` is `0.016`, an approximation of `1/64`.
- **No custom HUD.** The app relies on the system indicator. If step 5 above shows no indicator
  for brightness, one is needed.
- **External displays are out of scope.** Built-in only; no DDC.
- **The Accessibility grant does not survive a rebuild** while the app is ad-hoc signed, and the
  app looks enabled while it isn't. `make reset-permission` after each build, or sign with a stable
  self-signed certificate. See "Expect to re-grant permission after every rebuild" above.
- **The event tap subscribes to every event type**, because per-type subscription is reported not
  to be honoured for gesture events. That means the tap callback runs for every event in the
  session. It does nothing but count and return for types it ignores, but if the tap starts being
  disabled by timeout under load, the narrow mask is kept commented in
  `EventTapTouchSource.swift` as the thing to try.
- **Touch ids are only assumed unique among fingers currently down.** After a finger lifts, the OS
  could in principle give a later finger the same id. Nothing exploits that today — a rejected or
  engaged id is only consulted while it keeps appearing in frames — but it is why the diagnostics
  window prints raw ids.
- **The CoreAudio backend clears mute on the way up only.** Sliding down on a muted device leaves
  it muted, deliberately. The media-key backend gets mute handling from the OS.

---

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture, rejected alternatives, risk table
- [`docs/plans/2026-07-27-trackpad-edge-gestures.md`](docs/plans/2026-07-27-trackpad-edge-gestures.md)
  — implementation plan and verification status

## Prior art

This is a from-scratch reimplementation of an idea sold commercially as
[Slidr](https://slidr.xyz) ($4.99). No Slidr code was seen or used — it is closed source. Its
changelog was, however, genuinely instructive: v1.0 shipped the gesture, and bottom-quarter mode,
typing detection, cursor freeze and modifier keys all arrived across v1.1–v1.3. Those are not
features, they are false-positive fixes found in daily use, and shipping them in v1 here is the
most valuable thing this project borrowed.

If you want something that works today rather than something you have to debug, buy Slidr.

## License

MIT — see [LICENSE](LICENSE).
