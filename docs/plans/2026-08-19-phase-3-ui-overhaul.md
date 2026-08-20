# Phase 3 -- UI Overhaul: 4-Edge Gestures, Interactive Preview, and Settings Improvements

## Goal

Expand Ledge from 2-edge (left/right vertical) to 4-edge (left/right/top/bottom) gesture
support with per-edge configurable actions, an interactive trackpad preview that replaces the
old static band visualization, and several Settings window UX improvements.

The core architecture remains the same: `LedgeCore` is the fully tested decision layer; the
macOS adapter (`Sources/Ledge/`) is a thin I/O shell. This phase adds new decision paths to
LedgeCore (horizontal gesture logic, edge priority, per-edge configuration) and new adapter
code (action handlers for zoom/scroll/next-previous track, interactive preview UI, Dock
activation policy management).

---

## LedgeCore Changes

All files in `Sources/LedgeCore/`. Fully tested on Linux via `swift test`.

### New Types (`Controls.swift`)

| Type | Purpose |
|------|---------|
| `TrackpadEdge` (enum, 4 cases) | `.left`, `.right`, `.top`, `.bottom` -- names a physical edge |
| `EdgeAction` (enum, 6 cases) | `.volume`, `.brightness`, `.zoom`, `.nextPreviousTrack`, `.scroll`, `.none` -- what a gesture drives |
| `EdgeConfig` (struct) | Per-edge config: `action: EdgeAction`, `bandWidth: Double`, `isEnabled: Bool` |

`EdgeAction` conforms to `RawRepresentable` (String), `Sendable`, `Equatable`, `CaseIterable`
and provides a `displayName` computed property for UI labels.

The legacy `Control` enum (`.volume`, `.brightness`) is kept for backward compatibility with
any code that still references it, but is no longer used by the gesture engine.

### GestureSettings (`GestureSettings.swift`)

Replaced:
- `edgeBandWidth: Double` (single value for both edges)
- `swapSides: Bool`

With:
- `leftEdge: EdgeConfig` (default: brightness, 0.025, enabled)
- `rightEdge: EdgeConfig` (default: volume, 0.025, enabled)
- `topEdge: EdgeConfig` (default: none, 0.025, disabled)
- `bottomEdge: EdgeConfig` (default: none, 0.025, disabled)

New methods:
- `edgeConfig(for:)` -- returns the `EdgeConfig` for a given `TrackpadEdge`
- `edge(forPosition:)` -- classifies a `NormalizedPoint` into the appropriate edge (or nil)

Removed:
- `edge(forX:)` -- replaced by `edge(forPosition:)`
- `control(for:)` -- per-edge action assignment replaces control mapping

#### Edge Priority Rules

`edge(forPosition:)` checks vertical edges first (left/right based on x-coordinate), then
horizontal edges (top/bottom based on y-coordinate). Vertical edges always win in corners.
Within the same axis, overlapping bands resolve to the nearer edge, with ties going to left
(horizontal) or bottom (vertical). Disabled edges are never returned.

### GestureEvent (`GestureEvent.swift`)

Changed from:
```swift
case engaged(Control)
case step(Control, StepDirection)
case disengaged(Control)
```

To:
```swift
case engaged(TrackpadEdge, EdgeAction)
case step(TrackpadEdge, EdgeAction, StepDirection)
case disengaged(TrackpadEdge)
```

Every `.engaged` is still followed by exactly one `.disengaged` for the same edge.

### GestureEngine (`GestureEngine.swift`)

Major changes to the state machine:

1. **Arming:** Uses `settings.edge(forPosition:)` to detect all 4 edges. The `Arming` struct
   stores the detected `TrackpadEdge`.

2. **Activation (vertical edges - left/right):** Primary axis is y. Engage when
   `abs(dy) > activationDistance`. Reject if `abs(dy) <= abs(dx)` (finger is moving
   more horizontally than vertically).

3. **Activation (horizontal edges - top/bottom):** Primary axis is x. Engage when
   `abs(dx) > activationDistance`. Reject if `abs(dx) <= abs(dy)` (finger is moving
   more vertically than horizontally).

4. **Engagement struct:** Replaced `Control` with `TrackpadEdge` + `EdgeAction`. Uses
   `baseCoordinate` (y for vertical edges, x for horizontal) instead of `baseY`. The
   `advance(to:)` method now takes the relevant axis coordinate.

5. **Drift checking:** For left/right, checks x-position against `bandWidth + maxDriftOutsideBand`.
   For top/bottom, checks y-position against the same threshold on the relevant axis.

6. **Step direction for horizontal edges:** Positive x-travel (rightward) = `.up`, negative
   x-travel (leftward) = `.down`. This mirrors vertical edge behavior where positive y-travel
   (upward) = `.up`.

---

## macOS Adapter Changes

All files in `Sources/Ledge/`. Cannot be compiled on Linux. Uncertainties are marked with
`// UNVERIFIED:` comments throughout.

### GestureController (`GestureController.swift`)

- Replaced `engagedControl: Control?` with `engagedEdge: TrackpadEdge?` and
  `engagedAction: EdgeAction?`
- `apply(_:)` handles new event shapes (`.engaged(edge, action)`, `.step(edge, action, dir)`,
  `.disengaged(edge)`)
- New `perform(_:_:)` method dispatches on `EdgeAction`:
  - `.volume` -- existing volume backend (media keys or CoreAudio)
  - `.brightness` -- existing `BrightnessController` + media key post
  - `.zoom` -- synthesizes `Cmd+=` (zoom in) / `Cmd+-` (zoom out) via `CGEvent`
  - `.nextPreviousTrack` -- synthesizes `NX_KEYTYPE_NEXT` (17) / `NX_KEYTYPE_PREVIOUS` (18) via `NSEvent.otherEvent(with: .systemDefined, ...)`
  - `.scroll` -- synthesizes `CGEvent(scrollWheelEvent2Source:...)` with line delta +/-3
  - `.none` -- no-op

### Preferences (`Preferences.swift`)

- Per-edge keys: `{edge}Action`, `{edge}BandWidth`, `{edge}Enabled` for each of left/right/top/bottom
- Registered defaults sourced from `GestureSettings()` (single source of truth)
- Migration logic (`migrateIfNeeded()`):
  - Detects old format: `edgeBandWidth` and/or `swapSides` keys explicitly set
  - Maps old values: left gets brightness (or volume if swapSides was true), right gets volume (or brightness)
  - Top/bottom initialized to disabled with `action: .none`
  - Old keys removed after migration, sentinel `perEdgeMigrated` prevents re-running
  - Fresh installs skip migration entirely

### InteractiveTrackpadPreview (`TrackpadPreviewView.swift`)

- Renamed from the old `TrackpadPreviewView` to `InteractiveTrackpadPreview` (the legacy
  struct is kept for `OnboardingView` backward compatibility)
- Full interactive 4-edge preview: rounded rectangle trackpad with edge bands on all sides
- Each band is draggable to resize width
- Click to toggle enable/disable
- Enabled: blue at opacity 0.3; disabled: gray at opacity 0.15
- Action pickers positioned outside the trackpad shape (above/below/left/right)
- Uses `@Binding var {edge}: EdgeConfig` so changes propagate to `SettingsViewModel`

### GestureSettingsTab (`GestureSettingsTab.swift`)

- Replaced old layout (single edgeBandWidth slider, swapSides toggle) with
  `InteractiveTrackpadPreview` taking per-edge bindings
- Removed "Edge Band Width" slider (now per-edge via drag)
- Removed "Swap Sides" toggle (now per-edge action assignment)
- Kept Activation Distance slider and Fine Control toggle

### SettingsWindow (`SettingsWindow.swift`)

- `show()` calls `NSApp.setActivationPolicy(.regular)` so the app appears in the Dock
  - Provides Cmd+W close behavior automatically
  - App icon visible for window switching
- `windowWillClose(_:)` calls `NSApp.setActivationPolicy(.accessory)` to hide from Dock
- Sidebar toggle removed (via `.toolbar(removing: .sidebarToggle)` or balanced split style)

### SettingsIO (`SettingsIO.swift`)

- Format bumped to version 2 with per-edge configuration in exports
- Version 1 import backward compatibility: maps `edgeBandWidth`/`swapSides` to per-edge config

### Other Adapter Updates

- `AppDelegate` -- uses `engagedEdge`/`engagedAction` instead of `engagedControl`
- `DiagnosticsWindow` -- updated for per-edge bandWidth display
- `MenuBarController` -- references new API surface
- `OnboardingView` -- keeps legacy `TrackpadPreviewView` for its simpler visualization

---

## Migration Strategy

| Old Key | Maps To |
|---------|---------|
| `edgeBandWidth` | All four `{edge}BandWidth` keys get this value |
| `swapSides = false` | left = brightness, right = volume |
| `swapSides = true` | left = volume, right = brightness |
| (absent) | top/bottom initialized disabled with `.none` action |

Migration runs once on first read. The `perEdgeMigrated` sentinel key prevents it from
running again. Old keys are removed after migration.

---

## Testing

All tests in `Tests/LedgeCoreTests/`. 97 tests total, all passing.

### Rewritten Tests (62 tests across 5 files)

Every existing test was updated for the new API surface:
- `GestureSettingsTests.swift` -- tests for `edge(forPosition:)`, per-edge config, priority
  rules, disabled edges. Old `edge(forX:)` and `swapSides` tests removed.
- `GestureEngineArmingTests.swift` -- all `.engaged(.brightness)` updated to
  `.engaged(.left, .brightness)` etc.
- `GestureEngineSteppingTests.swift` -- all `.step(.volume, .up)` updated to
  `.step(.right, .volume, .up)` etc.
- `GestureEngineGuardTests.swift` -- all `.disengaged(.volume)` updated to
  `.disengaged(.right)` etc.
- `ModifierKeyTests.swift` -- event assertions updated.
- `GeometryTests.swift` -- unchanged (NormalizedPoint/TouchFrame untouched).

### New Tests: FourEdgeTests.swift (25 tests)

Dedicated horizontal/4-edge coverage:
- Top edge detection (y > 1-bandWidth)
- Bottom edge detection (y < bandWidth)
- Horizontal gesture activation (dx as primary axis)
- Horizontal stepping (right = .up, left = .down)
- Corner priority (vertical wins over horizontal)
- Disabled edge never arms
- Per-edge bandWidth works independently
- Y-drift beyond tolerance ends horizontal gesture
- Mid-gesture settings snapshot for horizontal edges

### New Tests in GestureSettingsTests.swift (10 tests)

- EdgeConfig defaults
- EdgeAction enum coverage
- `edgeConfig(for:)` correctness
- Priority and classification edge cases

---

## Known Limitations and UNVERIFIED Items

The following are marked with `// UNVERIFIED:` in the macOS adapter source because they cannot
be compiled or tested in the Linux sandbox:

1. **Zoom action key codes** (`GestureController.swift`): CGEvent key code 24 (`=`) and 27
   (`-`) assume US keyboard layout. Non-US layouts may map these physical keys differently.

2. **Transport media key constants** (`GestureController.swift`): `NX_KEYTYPE_NEXT = 17` and
   `NX_KEYTYPE_PREVIOUS = 18` from `IOKit/hidsystem/ev_keymap.h`. These are not modularized
   for Swift import and could theoretically change.

3. **Scroll delta tuning** (`GestureController.swift`): Delta value of +/-3 lines may need
   adjustment for comfortable scrolling speed.

4. **Dock activation policy transitions** (`SettingsWindow.swift`):
   `NSApp.setActivationPolicy(.regular)` while already running as `.accessory` should work
   but may have edge cases with window ordering or a brief Dock icon flicker on close.

5. **DragGesture in GeometryReader** (`TrackpadPreviewView.swift`): Coordinate system behavior
   within nested geometry readers on macOS 14+ may need attention.

6. **NSEvent.otherEvent for transport keys** (`GestureController.swift`): Construction of
   system-defined events for next/previous track may behave differently than volume/brightness
   keys on some macOS versions.

7. **CGEvent scrollWheelEvent2Source availability** (`GestureController.swift`): Using `.line`
   units for discrete scroll steps; behavior across macOS versions is assumed consistent but
   not verified.

---

## What Was Deferred

| Item | Reason |
|------|--------|
| **Keyboard shortcut action** (`EdgeAction.keyboardShortcut`) | Requires a UI for the user to record an arbitrary key combination. More complex than a simple enum case; deferred to a future phase where a "record shortcut" sheet can be designed properly. |

---

## Design Decisions

1. **Vertical priority in corners:** When a finger lands in both a vertical and horizontal
   band (e.g., bottom-left corner), vertical edges win. This avoids ambiguous gesture
   activation and matches the more common use case (volume/brightness on left/right).

2. **StepDirection mapping for horizontal edges:** Rightward = `.up`, leftward = `.down`.
   Chosen for consistency with the "more = up" mental model (volume up = slide up on
   right edge; zoom in = slide right on top edge).

3. **Legacy Control enum kept:** Not removed because `OnboardingView` and potentially other
   downstream code may reference it. It is inert in the gesture system.

4. **InteractiveTrackpadPreview vs TrackpadPreviewView:** Renamed to avoid collision with the
   simpler onboarding preview. The onboarding flow does not need per-edge configuration UI.

5. **SettingsIO version 2:** Breaking change in export format (per-edge config replaces flat
   fields), but version 1 imports are handled transparently.

6. **Migration is one-shot:** Runs on first `Preferences` init, then never again. This avoids
   accidental re-migration if a user later deletes a per-edge key manually.

---

## File Inventory

### LedgeCore (cross-platform, tested)
- `Sources/LedgeCore/Controls.swift` -- TrackpadEdge, EdgeAction, EdgeConfig, Control, StepDirection
- `Sources/LedgeCore/GestureSettings.swift` -- per-edge config, edge(forPosition:), priority logic
- `Sources/LedgeCore/GestureEngine.swift` -- state machine with horizontal gesture support
- `Sources/LedgeCore/GestureEvent.swift` -- updated event enum with edge + action
- `Sources/LedgeCore/TouchFrame.swift` -- unchanged
- `Sources/LedgeCore/Geometry.swift` -- unchanged
- `Sources/LedgeCore/ModifierKeyMode.swift` -- unchanged

### macOS Adapter (macOS-only, UNVERIFIED)
- `Sources/Ledge/GestureController.swift` -- action dispatch for all 6 EdgeAction cases
- `Sources/Ledge/Preferences.swift` -- per-edge storage, migration
- `Sources/Ledge/TrackpadPreviewView.swift` -- InteractiveTrackpadPreview (4-edge, draggable)
- `Sources/Ledge/GestureSettingsTab.swift` -- uses interactive preview
- `Sources/Ledge/SettingsView.swift` -- per-edge ViewModel bindings
- `Sources/Ledge/SettingsWindow.swift` -- Dock activation policy
- `Sources/Ledge/SettingsIO.swift` -- v2 format with backward-compatible v1 import

### Tests
- `Tests/LedgeCoreTests/GestureSettingsTests.swift` -- 10 new + rewritten
- `Tests/LedgeCoreTests/GestureEngineArmingTests.swift` -- rewritten
- `Tests/LedgeCoreTests/GestureEngineSteppingTests.swift` -- rewritten
- `Tests/LedgeCoreTests/GestureEngineGuardTests.swift` -- rewritten
- `Tests/LedgeCoreTests/ModifierKeyTests.swift` -- rewritten
- `Tests/LedgeCoreTests/GeometryTests.swift` -- unchanged
- `Tests/LedgeCoreTests/FourEdgeTests.swift` -- 25 new tests for horizontal/4-edge logic
