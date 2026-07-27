# Ledge — Implementation Plan

Derived from `DESIGN.md`. Tasks are ordered so that everything testable is proven before
anything untestable is written.

## Phase 1 — Package skeleton

- [x] `Package.swift` with two targets. `LedgeCore` is cross-platform; the `Ledge`
      executable target is added only under `#if os(macOS)` in the manifest, so
      `swift build` and `swift test` both succeed on Linux.
- [x] `.gitignore`, MIT `LICENSE`, initial `README.md`.

**Verification:** `swift build` and `swift test` succeed on Linux.

## Phase 2 — LedgeCore value types

- [x] `NormalizedPoint` — 0...1, origin lower-left, matching `NSTouch.normalizedPosition`.
- [x] `TouchPoint`, `TouchFrame`.
- [x] `TrackpadEdge` (`.left` / `.right`), `Control` (`.volume` / `.brightness`),
      `StepDirection` (`.up` / `.down`).
- [x] `GestureSettings` with documented defaults.
- [x] `GestureEvent` — `.engaged`, `.step`, `.disengaged`.

**Verification:** compiles; defaults asserted in tests.

## Phase 3 — GestureEngine, test-first

Each item is a RED-GREEN cycle: write the failing test, then the minimum code to pass.

- [x] A touch starting outside the edge band never engages.
- [x] A touch starting inside the band does not engage until vertical travel exceeds
      `activationDistance`.
- [x] Once engaged, sliding up emits `.step(_, .up)`; sliding down emits `.step(_, .down)`.
- [x] Number of steps emitted equals `floor(travel / effectiveStepDistance)`.
- [x] Anchoring: a long continuous slide emits steps at exact intervals with no drift.
- [x] Left band maps to brightness, right band to volume; `swapSides` inverts this.
- [x] `fineControl == false` multiplies the effective step distance by 4.
- [x] A second touch appearing disengages.
- [x] Drifting out of the band beyond tolerance disengages.
- [x] A gesture beginning predominantly horizontally never engages.
- [x] Typing within `typingLockout` suppresses engagement.
- [x] A frame gap longer than `gestureTimeout` restarts the gesture instead of resuming.
- [x] `bottomQuarterOnly` rejects touches starting above y = 0.25.
- [x] Lifting the finger emits `.disengaged` exactly once.
- [x] `isEnabled == false` suppresses everything.

**Verification:** `swift test` green on Linux. This is the only layer with real test coverage
and it is where the product logic lives.

## Phase 4 — macOS layer (cannot be compiled here)

Written blind. Every file is annotated with what must be verified on device.

- [x] `Permissions.swift` — `AXIsProcessTrustedWithOptions` check and prompt.
- [x] `EventTapTouchSource.swift` — tap on gesture events + `keyDown` for the typing signal
      + `mouseMoved`/`leftMouseDragged` swallowing for cursor freeze. Handles tap
      disable-by-timeout re-enable.
- [x] `MediaKeySender.swift` — `systemDefined` subtype 8 events.
- [x] `VolumeController.swift` — media-key backend (default) and CoreAudio backend.
- [x] `BrightnessController.swift` — `DisplayServices` via `dlopen`/`dlsym`, built-in
      display lookup, graceful degradation.
- [x] `Haptics.swift`.
- [x] `Preferences.swift` — `UserDefaults`, seeded from `GestureSettings` defaults.
- [x] `GestureController.swift` — wires source → engine → controllers → haptics.
- [x] `MenuBarController.swift` — status item, toggles, launch-at-login via `SMAppService`.
- [x] `DiagnosticsWindow.swift` — live touch and level readout.
- [x] `AppDelegate.swift`, `main.swift`.

## Phase 5 — Packaging

- [x] `Resources/Info.plist` — `LSUIElement`, stable bundle id `xyz.tuyennedd.ledge`.
- [x] `Makefile` — `make build`, `make app`, `make install`, ad-hoc `codesign`.

## Phase 6 — Review

- [x] Self-review of every macOS file against the API signatures it calls.
- [x] README with build instructions, permission setup, and an explicit list of unverified
      behaviour.

## On-device verification checklist

Nothing below can be done from the development sandbox. In rough order of importance —
if step 1 fails, nothing else matters.

1. **Does the event tap deliver single-finger touches?** Launch, grant Accessibility, open
   Diagnostics, rest one finger on the trackpad. If touch count and position update, the
   core assumption holds. If they never update, the event tap approach is dead and
   `MultitouchSupport` becomes necessary.
2. **Volume steps.** Slide the right edge. Confirm volume changes and the system HUD appears.
3. **Fine granularity.** Watch the volume figure in Diagnostics. Steps of ~1.6% mean the
   `.shift`+`.option` flags are honoured; ~6.25% means they are ignored and fine mode is a
   no-op worth removing.
4. **Brightness.** Slide the left edge. Confirm brightness changes, and note whether any
   system indicator appears — this determines whether a custom HUD is needed.
5. **Haptics.** Confirm one pulse per step and that it does not feel noisy.
6. **False positives.** Use the machine normally for a day: scroll, type, drag. Track
   unintended changes. Tune `edgeBandWidth`, `activationDistance`, `typingLockout`, and
   enable `bottomQuarterOnly` if needed.
7. **Cursor freeze.** Confirm the pointer holds still during a gesture and that mouse input
   is not left stuck afterwards.
8. **Permission persistence.** Rebuild, relaunch, confirm whether Accessibility must be
   re-granted.
