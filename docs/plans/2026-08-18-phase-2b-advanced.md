# Phase 2b — Modifier Key, Per-App Disable, Auto-Update, Export/Import

## Goal

Four features that make Ledge ready for daily use by power users and shareable with confidence:
a modifier key gate for zero false positives, per-app exclusions, automatic updates via Sparkle,
and portable settings.

## Scope

| # | Feature |
|---|---|
| 1 | Modifier key requirement (hold a key to enable gestures) |
| 2 | Per-app disable list (file picker + "Add current app") |
| 3 | Auto-update via Sparkle + GitHub Pages appcast |
| 4 | Export/import settings as JSON |

---

## Task 1: Modifier key requirement

**Files:**
- Modify: `Sources/LedgeCore/GestureSettings.swift` — add `modifierKeyRequired: ModifierKeyMode`
- Create: `Sources/LedgeCore/ModifierKeyMode.swift` — enum: `.none`, `.holdOption`, `.holdFn`, `.holdControl`
- Modify: `Sources/LedgeCore/GestureEngine.swift` — check modifier state before arming
- Modify: `Sources/Ledge/EventTapTouchSource.swift` — track current modifier flags
- Modify: `Sources/Ledge/GestureController.swift` — pass modifier state to engine
- Modify: `Sources/Ledge/Preferences.swift` — persist modifier key setting
- Modify: `Sources/Ledge/SettingsView.swift` (BehaviorSettingsTab) — picker for modifier key
- Tests: add to LedgeCoreTests

**Design:**
- `GestureEngine` gets a new method: `setModifierFlags(_ flags: Set<ModifierKey>)` or a simpler
  `isModifierHeld: Bool` property that the adapter sets from flag events.
- When `modifierKeyRequired != .none`, the engine only arms if the required modifier is held.
- The adapter reads `.flagsChanged` events (already received in the tap) and updates the engine.
- Default: `.none` (backwards compatible — gestures work without holding anything).

**Commit:** `feat: add modifier key requirement for gesture activation`

---

## Task 2: Per-app disable list

**Files:**
- Create: `Sources/Ledge/AppExclusionList.swift` — model: array of bundle identifiers
- Modify: `Sources/Ledge/Preferences.swift` — persist excluded app list
- Modify: `Sources/Ledge/GestureController.swift` — check frontmost app before processing
- Modify: `Sources/Ledge/SettingsView.swift` — new section in Behavior tab with list + buttons
- Create: `Sources/Ledge/ExcludedAppsView.swift` — SwiftUI view: list of excluded apps, "+" (file picker), "Add Current App" button, "-" to remove

**Design:**
- `GestureController` checks `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` on each
  frame (or on app activation change via NSWorkspace notification).
- If the frontmost app's bundle ID is in the exclusion list, `engine.setEnabled(false)` is called.
  When the user switches away from an excluded app, `engine.setEnabled(true)`.
- The file picker filters for `.app` bundles and extracts the bundle identifier from the
  `Info.plist` inside the selected `.app`.
- "Add Current App" reads `NSWorkspace.shared.frontmostApplication` — but since Settings is
  frontmost when the button is pressed, it should use the *previous* frontmost app. Store it on
  app deactivation, or use a "pick the app you want to exclude" approach with the file picker
  as primary and "Add Current App" as a convenience (shows the last active app before Settings
  was opened).

**Commit:** `feat: add per-app disable list with file picker`

---

## Task 3: Auto-update via Sparkle

**Files:**
- Modify: `Package.swift` — add Sparkle as a dependency (SPM: `https://github.com/sparkle-project/Sparkle`, from "2.0.0")
- Create: `Sources/Ledge/UpdateController.swift` — wraps `SPUStandardUpdaterController`
- Modify: `Sources/Ledge/AppDelegate.swift` — initialize UpdateController
- Modify: `Sources/Ledge/MenuBarController.swift` — add "Check for Updates..." menu item
- Modify: `Resources/Info.plist` — add `SUFeedURL` pointing to GitHub Pages appcast
- Create: `docs/appcast.xml` — initial empty/template appcast (populated by CI)
- Modify: `.github/workflows/release.yml` — after uploading .dmg, generate/update appcast.xml
  and push to gh-pages branch
- Create: `.github/workflows/pages.yml` — deploy gh-pages branch to GitHub Pages (or configure
  in release.yml)

**Design:**
- `SUFeedURL` = `https://tuyennedd.github.io/ledge-control/appcast.xml`
- Sparkle's `SPUStandardUpdaterController` handles the entire check/download/install flow.
- The release workflow generates appcast entries using `generate_appcast` tool from Sparkle, or
  manually constructs the XML with the .dmg URL, version, and a Ed25519 signature.
- For Ed25519 signing: generate a key pair with `generate_keys` from Sparkle, store the private
  key as a GitHub secret, embed the public key in Info.plist (`SUPublicEDKey`).
- "Check for Updates..." in the menu triggers `updater.checkForUpdates()`.

**Note:** Sparkle requires the app to be signed and have a stable bundle ID — both already true.
It also works with ad-hoc signing for the update mechanism itself.

**Commit:** `feat: add auto-update via Sparkle with GitHub Pages appcast`

---

## Task 4: Export/import settings

**Files:**
- Create: `Sources/Ledge/SettingsIO.swift` — export Preferences to JSON, import from JSON
- Modify: `Sources/Ledge/SettingsView.swift` (GeneralSettingsTab or About) — "Export Settings"
  and "Import Settings" buttons
- Modify: `Sources/Ledge/GestureController.swift` — `applyPreferences()` after import

**Design:**
- Export: read all `GestureSettings` fields + adapter preferences, serialize to a JSON dict,
  present `NSSavePanel` with suggested name `ledge-settings.json`.
- Import: present `NSOpenPanel` for `.json` files, deserialize, write into `Preferences`,
  call `applyPreferences()`.
- The JSON includes a `version` field for future compat.
- Include: edgeBandWidth, stepDistance, activationDistance, maxDriftOutsideBand, bottomQuarterOnly,
  typingLockout, gestureTimeout, fineControl, swapSides, cursorFreezeEnabled, isEnabled,
  modifierKeyRequired, excludedApps.

**Commit:** `feat: add settings export/import as JSON`

---

## Implementation order

1 → 2 → 4 → 3

Rationale: modifier key and per-app need LedgeCore changes (testable). Export/import is
straightforward. Sparkle is the most complex (external dependency + CI changes) and goes last
so the other three can ship even if Sparkle integration hits issues.
