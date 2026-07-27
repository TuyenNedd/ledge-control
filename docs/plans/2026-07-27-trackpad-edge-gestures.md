# Trackpad Edge Gestures Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A macOS menu bar app that changes volume and brightness when you slide a finger along the left or right edge of the trackpad, with one haptic pulse per step.

**Architecture:** Two layers. `LedgeCore` is pure Swift with no system dependencies and holds every decision the app makes — it is fully unit tested. `Ledge` is a macOS-only shell of thin I/O adapters over CGEvent taps, media key synthesis, `DisplayServices`, and AppKit, containing no branching logic worth testing.

**Tech Stack:** Swift 6, SwiftPM, swift-testing, AppKit, CoreGraphics event taps, CoreAudio, `DisplayServices` (private, loaded via `dlsym`).

---

## Read First

`docs/DESIGN.md` records two OS findings that this plan depends on and that must not be
"optimised away" during implementation:

1. `OSDUIHelper` does not exist on macOS 26 Tahoe. The native HUD cannot be summoned directly.
   Volume therefore goes through synthesised media keys so that the OS performs the change and
   draws its own indicator.
2. Synthesised `NX_KEYTYPE_BRIGHTNESS_UP`/`DOWN` events do not change brightness, while the
   volume equivalents do. Brightness therefore needs `DisplayServices`.

## Environment Constraints — read before Task 7

Tasks 1–6 (`LedgeCore`) are developed in a Linux sandbox with Swift 6.2.1. `swift build` and
`swift test` run for real there. **These tasks follow strict TDD with no exceptions.**

Tasks 7–12 (`Sources/Ledge/`) **cannot be compiled or run in that sandbox** — no macOS, no
AppKit, no Apple hardware.

The TDD skill lists configuration files as an exception and otherwise requires human-partner
permission to skip. The human partner is unavailable, so this plan takes the narrowest possible
exemption and states it plainly:

- **Tasks 7–12 are exempt from TDD**, because the code cannot be executed at all in the
  development environment. A test that cannot run is not a test.
- The exemption is only defensible because of a deliberate architectural constraint: **no
  decision logic may live in `Sources/Ledge/`.** Every threshold, every mapping, every guard
  belongs in `LedgeCore` under test. If an implementer finds themselves writing an `if` that
  encodes product behaviour inside an adapter, that is a signal the logic belongs in
  `LedgeCore` instead.
- Verification for these tasks is deferred to the on-device checklist at the end of this plan.
  Until a human runs it, **the correct status of tasks 7–12 is "written, never executed."**

Do not mark anything in this plan complete on the basis that code was written. Complete means
verified by a command whose output was read.

## Deliberate deviations from the Superpowers workflow

| Skill | Deviation | Reason |
|---|---|---|
| `brainstorming` | Design was not validated section-by-section with the user | The user explicitly delegated all decisions and left. Design is recorded in `docs/DESIGN.md` for review after the fact. |
| `using-git-worktrees` | Work happens on branch `feat/trackpad-edge-gestures`, not a worktree | The sandbox holds one freshly cloned repo with no concurrent work and no dirty state. A branch provides the isolation a worktree would provide here. |

---

## Task 1: Package skeleton

**Files:**
- Create: `Package.swift`

Configuration file — the TDD skill's stated exception. Verified by building, not by unit test.

**Step 1: Write the manifest**

```swift
// swift-tools-version:6.0
import PackageDescription

var targets: [Target] = [
    .target(name: "LedgeCore", swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(
        name: "LedgeCoreTests",
        dependencies: ["LedgeCore"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Ledge",
        dependencies: ["LedgeCore"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
)
#endif

let package = Package(name: "Ledge", platforms: [.macOS(.v14)], targets: targets)
```

The `#if os(macOS)` guard is what keeps `swift build` and `swift test` working on Linux. The
executable stays in language mode 5 because AppKit predates `Sendable` and strict concurrency
produces only noise in a single-threaded, main-thread-bound shell.

**Step 2: Verify the manifest loads and the package builds**

Run: `swift build 2>&1 | tail -5`
Expected: no manifest error. A "Source files for target LedgeCore should be located under
Sources/LedgeCore" error is the expected next failure.

**Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: add SwiftPM manifest with platform-conditional app target"
```

---

## Task 2: Normalized geometry and touch frames

**Files:**
- Create: `Sources/LedgeCore/Geometry.swift`
- Create: `Sources/LedgeCore/TouchFrame.swift`
- Test: `Tests/LedgeCoreTests/GeometryTests.swift`

**Context:** `NSTouch.normalizedPosition` reports 0...1 with the origin at the **lower left** of
the trackpad, so y increases upward and "slide up" means increasing y. Encoding that convention
in a named type once stops it from being re-derived (and inverted) later.

**Step 1: Write the failing test**

```swift
import Testing
@testable import LedgeCore

@Test("y increases upward, matching NSTouch.normalizedPosition")
func normalizedPointOriginIsLowerLeft() {
    let lower = NormalizedPoint(x: 0.5, y: 0.1)
    let upper = NormalizedPoint(x: 0.5, y: 0.9)
    #expect(upper.isAbove(lower))
}

@Test("a frame reports the single touch it carries")
func frameCarriesTouches() {
    let frame = TouchFrame(
        timestamp: 1.0,
        touches: [TouchPoint(id: 7, position: NormalizedPoint(x: 0.02, y: 0.4))]
    )
    #expect(frame.touches.count == 1)
    #expect(frame.touches[0].id == 7)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `cannot find 'NormalizedPoint' in scope`

**Step 3: Write minimal implementation**

`NormalizedPoint` with `x`, `y` and `isAbove(_:)`. `TouchPoint` with `id`, `position`.
`TouchFrame` with `timestamp`, `touches`. All `Sendable`, `Equatable`, memberwise `public init`.

**Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS, 2 tests

**Step 5: Commit**

```bash
git add Sources/LedgeCore Tests/LedgeCoreTests
git commit -m "feat(core): add normalized geometry and touch frame types"
```

---

## Task 3: Edge classification and settings

**Files:**
- Create: `Sources/LedgeCore/Controls.swift`
- Create: `Sources/LedgeCore/GestureSettings.swift`
- Test: `Tests/LedgeCoreTests/GestureSettingsTests.swift`

**Context:** Which edge controls what, and how far a finger must travel per step, are the two
knobs that will be tuned most after real use. They belong in one tested place.

Defaults and their reasoning:

| Setting | Default | Reasoning |
|---|---|---|
| `edgeBandWidth` | `0.10` | ≈16 mm of a MacBook trackpad — wide enough to hit without aiming |
| `stepDistance` | `0.016` | ≈1/64 of height, matching the 64 sub-steps fine volume mode provides, so one full-height slide spans the whole range |
| `activationDistance` | `0.02` | Dead zone; must exceed a resting wobble |
| `maxDriftOutsideBand` | `0.06` | Tolerance before an engaged gesture is abandoned |
| `bottomQuarterOnly` | `false` | Available if false positives persist, off until proven necessary |
| `typingLockout` | `0.6` s | Long enough to cover a pause between keystrokes |
| `gestureTimeout` | `0.25` s | A stale gesture must not resume after a pause |
| `fineControl` | `true` | The entire point of the app |
| `swapSides` | `false` | Volume on the right, matching where a right hand rests |

**Step 1: Write the failing test**

```swift
import Testing
@testable import LedgeCore

@Test("x within the band classifies as an edge, the middle does not")
func edgeClassification() {
    let s = GestureSettings()
    #expect(s.edge(forX: 0.02) == .left)
    #expect(s.edge(forX: 0.98) == .right)
    #expect(s.edge(forX: 0.5) == nil)
}

@Test("left edge is brightness and right edge is volume by default")
func defaultControlMapping() {
    let s = GestureSettings()
    #expect(s.control(for: .left) == .brightness)
    #expect(s.control(for: .right) == .volume)
}

@Test("swapSides inverts the control mapping")
func swappedControlMapping() {
    var s = GestureSettings()
    s.swapSides = true
    #expect(s.control(for: .left) == .volume)
    #expect(s.control(for: .right) == .brightness)
}

@Test("disabling fine control makes each step four times longer")
func coarseStepDistance() {
    var s = GestureSettings()
    let fine = s.effectiveStepDistance
    s.fineControl = false
    #expect(s.effectiveStepDistance == fine * 4)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `cannot find 'GestureSettings' in scope`

**Step 3: Write minimal implementation**

`TrackpadEdge` (`.left`, `.right`), `Control` (`.volume`, `.brightness`), `StepDirection`
(`.up`, `.down`). `GestureSettings` with the fields above plus `edge(forX:)`,
`control(for:)`, `effectiveStepDistance`.

**Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS, 6 tests

**Step 5: Commit**

```bash
git add Sources/LedgeCore Tests/LedgeCoreTests
git commit -m "feat(core): add control types and tunable gesture settings"
```

---

## Task 4: Engine arming

**Files:**
- Create: `Sources/LedgeCore/GestureEvent.swift`
- Create: `Sources/LedgeCore/GestureEngine.swift`
- Test: `Tests/LedgeCoreTests/GestureEngineArmingTests.swift`

**Context:** Arming is the first half of false-positive prevention. A touch must *begin* inside
the edge band — a finger that drifts in mid-scroll is not a deliberate gesture — and must then
travel vertically past a dead zone before anything happens.

`GestureEvent` is `.engaged(Control)`, `.step(Control, StepDirection)`, `.disengaged(Control)`.
`process(frame:)` returns `[GestureEvent]`.

**Step 1: Write the failing test**

```swift
import Testing
@testable import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

@Test("a touch starting in the middle never engages")
func centreTouchNeverEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.5, 0.2))
    let events = engine.process(frame: frame(0.05, 0.5, 0.8))
    #expect(events.isEmpty)
}

@Test("a touch starting in the band does not engage before the dead zone is cleared")
func deadZoneSuppressesEngagement() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.02, 0.41))
    #expect(events.isEmpty)
}

@Test("clearing the dead zone engages the control for that edge")
func clearingDeadZoneEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.02, 0.45))
    #expect(events.first == .engaged(.brightness))
}

@Test("a gesture that starts out sideways never engages")
func horizontalGestureRejected() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.12, 0.43))
    #expect(events.isEmpty)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `cannot find 'GestureEngine' in scope`

**Step 3: Write minimal implementation**

State machine `idle → armed → engaged`, plus a `rejected(touchID:)` state so a touch that has
already disqualified itself is not re-evaluated every frame. On engaging, emit `.engaged` and
set the step anchor to the touch's **start** y, so travel already spent counts toward the first
step.

Reject at activation when `abs(dy) <= abs(dx)`.

**Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS, 10 tests

**Step 5: Commit**

```bash
git add Sources/LedgeCore Tests/LedgeCoreTests
git commit -m "feat(core): arm edge gestures behind a dead zone"
```

---

## Task 5: Stepping

**Files:**
- Modify: `Sources/LedgeCore/GestureEngine.swift`
- Test: `Tests/LedgeCoreTests/GestureEngineSteppingTests.swift`

**Context:** An anchor tracks the position that produced the last step and advances by exactly
`effectiveStepDistance` per emission. Anchoring rather than accumulating deltas keeps a long
slide from drifting, and gives direction changes a natural one-step hysteresis. One `.step`
event per step, so the haptic layer can pulse per event without doing arithmetic.

**Step 1: Write the failing test**

```swift
import Testing
@testable import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

@Test("sliding up emits upward steps")
func slidingUpStepsUp() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.45))
    let events = engine.process(frame: frame(0.10, 0.98, 0.55))
    #expect(events.allSatisfy { $0 == .step(.volume, .up) })
    #expect(!events.isEmpty)
}

@Test("sliding down emits downward steps")
func slidingDownStepsDown() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.60))
    _ = engine.process(frame: frame(0.05, 0.98, 0.55))
    let events = engine.process(frame: frame(0.10, 0.98, 0.45))
    #expect(events.contains(.step(.volume, .down)))
}

@Test("step count over a slide equals travel divided by step distance")
func stepCountMatchesTravel() {
    var engine = GestureEngine()
    let settings = GestureSettings()
    _ = engine.process(frame: frame(0.0, 0.98, 0.10))
    let events = engine.process(frame: frame(0.05, 0.98, 0.90))
    let steps = events.filter { $0 == .step(.volume, .up) }.count
    #expect(steps == Int((0.80 / settings.effectiveStepDistance).rounded(.down)))
}

@Test("anchoring keeps steps evenly spaced across many frames")
func anchoringDoesNotDrift() {
    var engine = GestureEngine()
    let settings = GestureSettings()
    _ = engine.process(frame: frame(0.0, 0.98, 0.10))
    var total = 0
    var y = 0.10
    var t = 0.0
    while y < 0.90 {
        y += 0.01
        t += 0.02
        total += engine.process(frame: frame(t, 0.98, y)).filter { $0 == .step(.volume, .up) }.count
    }
    #expect(total == Int((0.80 / settings.effectiveStepDistance).rounded(.down)))
}

@Test("lifting the finger disengages exactly once")
func liftingDisengagesOnce() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.50))
    let lift = engine.process(frame: TouchFrame(timestamp: 0.10, touches: []))
    #expect(lift == [.disengaged(.volume)])
    let after = engine.process(frame: TouchFrame(timestamp: 0.15, touches: []))
    #expect(after.isEmpty)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — no step events emitted

**Step 3: Write minimal implementation**

While engaged: `while y - anchor >= step { emit up; anchor += step }` and the mirror for down.
An empty touch list disengages.

**Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS, 15 tests

**Step 5: Commit**

```bash
git add Sources/LedgeCore Tests/LedgeCoreTests
git commit -m "feat(core): emit anchored steps while a gesture is engaged"
```

---

## Task 6: Guards

**Files:**
- Modify: `Sources/LedgeCore/GestureEngine.swift`
- Test: `Tests/LedgeCoreTests/GestureEngineGuardTests.swift`

**Context:** This is the task that decides whether the app is pleasant or infuriating. Slidr
shipped its gesture in v1.0 and then spent v1.1–v1.3 adding bottom-quarter mode, typing
detection, cursor freeze, and modifier keys. Those were not features, they were false-positive
fixes found in daily use. Building them now is the highest-value thing in this plan.

**Step 1: Write the failing test**

One test per guard:

- a second touch appearing disengages an active gesture
- drifting beyond `edgeBandWidth + maxDriftOutsideBand` disengages
- `noteTyping` inside `typingLockout` suppresses engagement
- `noteTyping` while engaged disengages
- a frame gap beyond `gestureTimeout` restarts rather than resumes the gesture
- `bottomQuarterOnly` rejects a touch starting above y = 0.25 and accepts one below
- `isEnabled == false` suppresses everything and disengages an active gesture

**Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -30`
Expected: FAIL on each guard not yet implemented

**Step 3: Write minimal implementation**

Add to `GestureEngine`: `isEnabled`, `noteTyping(at:) -> [GestureEvent]`,
`setEnabled(_:) -> [GestureEvent]`, `cancel() -> [GestureEvent]`, touch-count check,
drift check, timeout check, bottom-quarter check.

**Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS, all tests

**Step 5: Commit**

```bash
git add Sources/LedgeCore Tests/LedgeCoreTests
git commit -m "feat(core): guard gestures against accidental activation"
```

---

## Task 7: Volume output

**Files:**
- Create: `Sources/Ledge/MediaKeySender.swift`
- Create: `Sources/Ledge/VolumeController.swift`

TDD-exempt: cannot execute. No decision logic permitted here.

**Contract:**

- `MediaKeySender.post(_ key: MediaKey, fine: Bool)` builds an `NSEvent.otherEvent` of type
  `.systemDefined`, subtype `8` (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`), with
  `data1 = (keyCode << 16) | (isDown ? 0x0A00 : 0x0B00)` and `data2 = -1`, posting key-down
  then key-up via `cgEvent?.post(tap: .cghidEventTap)`. When `fine` is true the modifier flags
  are `[.shift, .option]`.
- `MediaKey`: `soundUp = 0`, `soundDown = 1`, `brightnessUp = 2`, `brightnessDown = 3`.
- `VolumeController.adjust(_ direction: StepDirection, fine: Bool)`.
- `CoreAudioVolumeController` as a selectable alternative using
  `kAudioDevicePropertyVolumeScalar` on the default output device. It produces no HUD, so it is
  not the default.
- `VolumeController.currentScalar() -> Float?` reading CoreAudio, for diagnostics only.

**Verify:** deferred to on-device checklist items 2 and 3.

**Commit:** `feat(app): drive volume through synthesised media keys`

---

## Task 8: Brightness output

**Files:**
- Create: `Sources/Ledge/BrightnessController.swift`

TDD-exempt: cannot execute. No decision logic permitted here.

**Contract:**

- Resolve `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`, and
  `DisplayServicesBrightnessChanged` from
  `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` using
  `dlopen` + `dlsym`. Missing symbols must leave the controller unavailable, not crash — a
  future macOS should cost brightness support, not the whole app.
- `isAvailable: Bool`.
- Resolve the built-in display via `CGGetActiveDisplayList` filtered by
  `CGDisplayIsBuiltin`, falling back to `CGMainDisplayID()`.
- `adjust(_ direction: StepDirection, fine: Bool)` reads current brightness, adds
  `±(fine ? 1/64 : 1/16)`, clamps to `0...1`, sets it, then calls
  `DisplayServicesBrightnessChanged` so the system can draw its own indicator.
- `currentBrightness() -> Float?` for diagnostics.

**Verify:** deferred to on-device checklist item 4.

**Commit:** `feat(app): drive built-in display brightness via DisplayServices`

---

## Task 9: Touch input

**Files:**
- Create: `Sources/Ledge/EventTapTouchSource.swift`
- Create: `Sources/Ledge/Permissions.swift`

TDD-exempt: cannot execute. **Highest-risk task in the plan** — if this does not deliver
single-finger touches, nothing else in the app matters.

**Contract:**

- `Permissions.isTrusted()` and `Permissions.requestIfNeeded()` wrapping
  `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt`.
- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, ...)`
  with a mask covering event type `29` (`NSEventTypeGesture`), `.keyDown`, `.flagsChanged`,
  `.mouseMoved`, and `.leftMouseDragged`.
- Convert gesture events with `NSEvent(cgEvent:)` and read `allTouches()`, keeping touches whose
  `type == .indirect`, mapping `identity.hash` to `TouchPoint.id` and `normalizedPosition` to
  `NormalizedPoint`.
- Emit a `TouchFrame` per gesture event through a callback.
- Report `.keyDown` and `.flagsChanged` through a separate typing callback.
- Return `nil` for `.mouseMoved` and `.leftMouseDragged` **only while a gesture is engaged and
  cursor freeze is on**, so the pointer holds still. Everything else passes through untouched.
- Handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` by re-enabling the tap;
  otherwise the app silently dies after a stall.

**Verify:** deferred to on-device checklist item 1.

**Commit:** `feat(app): read trackpad touches from a CGEvent tap`

---

## Task 10: Wiring

**Files:**
- Create: `Sources/Ledge/Haptics.swift`
- Create: `Sources/Ledge/Preferences.swift`
- Create: `Sources/Ledge/GestureController.swift`

TDD-exempt: cannot execute.

**Contract:**

- `Haptics.pulse()` calling
  `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`,
  guarded by a preference.
- `Preferences` backed by `UserDefaults`, seeded from `GestureSettings()` defaults, exposing
  `gestureSettings` plus `hapticsEnabled`, `cursorFreezeEnabled`, `isEnabled`,
  `useCoreAudioVolume`.
- `GestureController` owning the `GestureEngine`, subscribing to the touch source, and routing
  `.step` events to the matching controller and to `Haptics`. It must contain no thresholds —
  those live in `GestureSettings`.

**Commit:** `feat(app): wire touch input through the engine to system controls`

---

## Task 11: Menu bar and diagnostics

**Files:**
- Create: `Sources/Ledge/MenuBarController.swift`
- Create: `Sources/Ledge/DiagnosticsWindow.swift`
- Create: `Sources/Ledge/AppDelegate.swift`
- Create: `Sources/Ledge/main.swift`

TDD-exempt: cannot execute.

**Contract:**

- `NSStatusItem` with an SF Symbol, and toggles for enabled, swap sides, fine control,
  bottom-quarter-only, haptics, cursor freeze, CoreAudio volume backend, launch at login via
  `SMAppService.mainApp`, plus Diagnostics and Quit.
- `DiagnosticsWindow`: live readout of touch count, last normalized position, engine state,
  current volume scalar, current brightness, whether `DisplayServices` resolved, and whether
  the tap is enabled.

  This window is not a nicety. It is the only way to answer on-device checklist items 1 and 3
  without a debugger, and it is what makes a blind-written event tap diagnosable in seconds
  rather than by guesswork.
- `main.swift` sets `.accessory` activation policy and runs the app.

**Commit:** `feat(app): add menu bar controls and a diagnostics window`

---

## Task 12: Packaging

**Files:**
- Create: `Resources/Info.plist`
- Create: `Makefile`

**Contract:**

- `Info.plist` with `LSUIElement = true`, `CFBundleIdentifier = xyz.tuyennedd.ledge`,
  `LSMinimumSystemVersion = 14.0`.
- `Makefile` targets: `build`, `app` (assemble `dist/Ledge.app` and ad-hoc `codesign -s -`),
  `install` (copy to `/Applications`), `run`, `test`, `clean`.

A stable bundle identifier matters more than it looks: Accessibility permission is keyed to
bundle identity, and a changing one means re-granting permission on every rebuild.

**Step: Verify**

Run: `make app` on macOS
Expected: `dist/Ledge.app` exists and `codesign -dv dist/Ledge.app` reports an ad-hoc signature

**Commit:** `build: package the app bundle with an ad-hoc signature`

---

## Task 13: Documentation

**Files:**
- Modify: `README.md`

Build instructions, permission setup, tuning guidance, and an explicit, prominent statement of
what has never been executed. A reader must not be able to mistake written code for working
code.

**Commit:** `docs: document build, permissions, and verification status`

---

## On-device verification checklist

Nothing below can be done from the development sandbox. Ordered by consequence — if item 1
fails, nothing else matters.

- [ ] **1. Does the event tap deliver single-finger touches?** Launch, grant Accessibility,
      open Diagnostics, rest one finger on the trackpad. Touch count and position updating
      confirms the core assumption. If they never update, the event tap approach is dead and
      `MultitouchSupport` becomes necessary — see the rejected-alternatives note in
      `docs/DESIGN.md`.
- [ ] **2. Volume responds.** Slide the right edge. Volume changes and the system HUD appears.
- [ ] **3. Fine granularity is real.** Watch the volume scalar in Diagnostics. Steps of
      ≈1.6% mean the `.shift`+`.option` flags are honoured on synthesised events. Steps of
      ≈6.25% mean they are ignored, fine mode is a no-op, and it should be removed rather
      than left as a lie in the menu.
- [ ] **4. Brightness responds,** and note whether any system indicator appears. This decides
      whether a custom HUD is needed.
- [ ] **5. Haptics** fire once per step and do not feel noisy.
- [ ] **6. False positives.** Use the machine normally for a day. Track unintended changes.
      Tune `edgeBandWidth`, `activationDistance`, `typingLockout`; enable `bottomQuarterOnly`
      if needed.
- [ ] **7. Cursor freeze** holds the pointer still during a gesture and leaves no stuck input
      afterwards.
- [ ] **8. Permission persistence** across a rebuild and relaunch.
