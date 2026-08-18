# Phase 2a — Settings UI, Onboarding, and Build Workflow

## Goal

Transform Ledge from a "works but requires Terminal knowledge" app into one that feels
complete on first launch: a Settings window with live trackpad preview, a one-time onboarding
flow, visual feedback in the menu bar, and a build workflow that doesn't require re-granting
Accessibility after every recompile.

## Scope

| # | Feature |
|---|---|
| 1 | Self-signed certificate setup + Makefile `codesign --sign "Ledge Dev"` |
| 2 | `make reinstall` — one command: quit → install → relaunch |
| 3 | Settings window (SwiftUI, 3 tabs) |
| 4 | Trackpad preview in Gesture tab — live edge band visualization |
| 5 | Onboarding window on first launch |
| 6 | Menu bar icon highlight when gesture is engaged |

## Deferred to Phase 2b

- Modifier key requirement
- Per-app disable list
- Auto-update (Sparkle)
- Export/import settings

---

## Task 1: Self-signed certificate guide + Makefile update

**Files:**
- Modify: `Makefile`
- Create: `docs/CERTIFICATE.md`

**What:**
- Add `docs/CERTIFICATE.md` with step-by-step instructions to create a self-signed code signing
  certificate named "Ledge Dev" in Keychain Access (5 steps, with screenshots description)
- Update `Makefile`: change `codesign --force --sign -` to `codesign --force --sign "Ledge Dev"`
  with a fallback comment showing how to revert to ad-hoc if the cert doesn't exist
- Add a `SIGNING_IDENTITY` variable at the top defaulting to `"Ledge Dev"` so it can be
  overridden: `make app SIGNING_IDENTITY="-"` for ad-hoc
- Update `make reset-permission` comment to note it's only needed with ad-hoc signing
- Remove the `make reset-permission` step from `make reinstall` when using a cert

**Commit:** `build: add self-signed certificate guide and configurable signing identity`

---

## Task 2: `make reinstall`

**Files:**
- Modify: `Makefile`

**What:**
A single target that:
1. `osascript -e 'quit app "Ledge"'` (graceful quit, ignores error if not running)
2. `sleep 1` (wait for process to exit)
3. Runs the `install` target
4. `open /Applications/Ledge.app`

**Commit:** `build: add make reinstall for one-command rebuild cycle`

---

## Task 3: Settings window structure (SwiftUI)

**Files:**
- Create: `Sources/Ledge/SettingsWindow.swift` — the SwiftUI window
- Create: `Sources/Ledge/SettingsView.swift` — root TabView
- Create: `Sources/Ledge/GestureSettingsTab.swift` — Gesture tab
- Create: `Sources/Ledge/BehaviorSettingsTab.swift` — Behavior tab  
- Create: `Sources/Ledge/AboutTab.swift` — About tab
- Modify: `Sources/Ledge/MenuBarController.swift` — add "Settings..." menu item
- Modify: `Sources/Ledge/AppDelegate.swift` — own the settings window

**What:**
- SwiftUI `Settings` scene or `NSHostingController` wrapping the view in a borderless NSWindow
  (since the app doesn't use SwiftUI App lifecycle, use NSHostingController in an NSWindow)
- TabView with .tabViewStyle(.automatic) for the native segmented tabs
- Gesture tab: trackpad preview (Task 4), edge width slider (0.01–0.10, step 0.005, shows mm),
  activation distance slider, fine control toggle, swap sides toggle
- Behavior tab: cursor freeze toggle, typing lockout slider (0.2–2.0s), bottom quarter only
  toggle, gesture timeout slider
- About tab: app icon, version, "Ledge — trackpad edge gestures for volume & brightness",
  link to GitHub repo
- Menu item "Settings..." with ⌘, shortcut opens the window
- Window is `.titled, .closable`, not resizable, fixed size ~500x400
- Changes apply immediately (write to Preferences, call controller.applyPreferences())

**Commit:** `feat(app): add Settings window with three tabs`

---

## Task 4: Trackpad preview with live edge band visualization

**Files:**
- Create: `Sources/Ledge/TrackpadPreviewView.swift`

**What:**
- A SwiftUI View showing a rounded rectangle representing the trackpad
- Left and right edge bands drawn as semi-transparent blue overlays
- Width updates in real-time as the slider changes
- Shows numeric labels: "4mm" or whatever the current width corresponds to
- Trackpad proportions: roughly 3:2 aspect ratio (like a real MacBook trackpad)
- Labels "Brightness" on left band, "Volume" on right band (swap when swapSides is on)
- Subtle grid or trackpad texture (optional, a simple rounded rect with subtle border is fine)

**Commit:** `feat(app): add trackpad preview with live edge band visualization`

---

## Task 5: Onboarding window

**Files:**
- Create: `Sources/Ledge/OnboardingWindow.swift`
- Modify: `Sources/Ledge/Preferences.swift` — add `hasCompletedOnboarding: Bool`
- Modify: `Sources/Ledge/AppDelegate.swift` — show onboarding on first launch

**What:**
3 pages (next/back navigation):
1. **Welcome** — app icon, "Welcome to Ledge", one-sentence description
2. **Permission** — explains Accessibility is needed, button to open System Settings,
   live check showing whether permission is granted (poll AXIsProcessTrusted)
3. **Try it** — shows the trackpad preview, instructs "Slide along the right edge now",
   live feedback showing when a gesture is detected (subscribe to step count changing)

After completing: set `hasCompletedOnboarding = true`, close window, app is ready.
If permission is not granted by page 3, still allow closing but show a note.

**Commit:** `feat(app): add first-launch onboarding flow`

---

## Task 6: Menu bar icon highlight when engaged

**Files:**
- Modify: `Sources/Ledge/MenuBarController.swift`
- Modify: `Sources/Ledge/GestureController.swift` — add callback for engagement state

**What:**
- When a gesture is engaged, change the menu bar icon to a filled/highlighted variant
  (e.g. "slider.vertical.3" → custom tinted, or swap to a different symbol)
- Actually simplest: `statusItem.button?.appearsDisabled = false` normally,
  and add a colored background or use `contentTintColor` when engaged
- Add a callback `var onEngagementChanged: ((Bool) -> Void)?` to GestureController
- MenuBarController subscribes and updates the icon appearance
- Must be responsive (called from apply() which is on main thread, so UI update is safe)

**Commit:** `feat(app): highlight menu bar icon during active gesture`

---

## Implementation notes

- All SwiftUI code goes in `Sources/Ledge/` (macOS-only, cannot be compiled here)
- Use `@Observable` (macOS 14+) for the settings view model, reading from Preferences
- The Ledge target is in Swift language mode 5, which is fine for SwiftUI on macOS 14
- Minimum deployment target is already macOS 14 in Package.swift
- Onboarding and Settings are independent windows — neither blocks the other
