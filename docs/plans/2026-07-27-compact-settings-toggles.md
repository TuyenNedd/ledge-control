# Compact Settings Toggles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the five inline settings toggles with compact, trailing-aligned native macOS switch rows while keeping the settings window at 900×650.

**Architecture:** Add one stateless SwiftUI `SettingsToggleRow` that receives a title, description, and `Binding<Bool>`. Its native Toggle label contains the visible title and description, preserving the label click target and accessibility association while the system switch style positions the compact control at the trailing edge. Migrate existing toggle markup to the shared row without changing model bindings or side effects, and keep the root view at 900×650.

**Tech Stack:** Swift 6 package tools, SwiftUI, AppKit, Swift Package Manager, macOS 14+ (the AppKit executable target intentionally uses Swift 5 language mode)

---

### Task 1: Add the shared compact toggle row

**Files:**
- Create: `Sources/Ledge/SettingsToggleRow.swift`

**Step 1: Add the native settings row**

Create a stateless `SettingsToggleRow` with this structure:

```swift
import SwiftUI

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}
```

The visible title and description form the native Toggle label, so the label remains clickable and VoiceOver receives one control with a title and descriptive hint. The system switch is compact and trailing-aligned.

**Step 2: Compile the new component**

Run: `swift build`
Expected: `Build complete!` with no compiler errors.

**Step 3: Commit**

```bash
git add Sources/Ledge/SettingsToggleRow.swift
git commit -m "feat(ui): add compact settings toggle row"
```

### Task 2: Migrate General settings and restore the window frame

**Files:**
- Modify: `Sources/Ledge/SettingsView.swift:60-94`

**Step 1: Restore the SwiftUI root frame**

Change the pre-existing local `.frame(width: 680, height: 500)` back to:

```swift
.frame(width: 900, height: 650)
```

Do not change `SettingsWindow.swift`; its 900×650 initial content size and `.resizable` style are already correct.

**Step 2: Replace the General toggle blocks**

Replace “Enable Ledge” and “Launch at Login” Toggle-plus-caption blocks with `SettingsToggleRow`, preserving their current custom bindings exactly:

```swift
SettingsToggleRow(
    title: "Enable Ledge",
    description: "Master switch for all edge gestures.",
    isOn: Binding(
        get: { viewModel.isEnabled },
        set: { viewModel.isEnabled = $0 }
    )
)

SettingsToggleRow(
    title: "Launch at Login",
    description: "Start Ledge automatically when you log in.",
    isOn: Binding(
        get: { viewModel.launchAtLogin },
        set: { viewModel.launchAtLogin = $0 }
    )
)
.padding(.top, 8)
```

Use the exact existing description strings if they differ from the examples above.

**Step 3: Compile the General tab migration**

Run: `swift build`
Expected: `Build complete!` with no compiler errors.

**Step 4: Commit**

```bash
git add Sources/Ledge/SettingsView.swift
git commit -m "refactor(ui): use compact rows in general settings"
```

### Task 3: Migrate Behavior and Gesture settings

**Files:**
- Modify: `Sources/Ledge/BehaviorSettingsTab.swift:10-30`
- Modify: `Sources/Ledge/GestureSettingsTab.swift:65-75`

**Step 1: Replace Behavior toggle blocks**

Replace “Freeze Cursor During Gesture” and “Bottom Quarter Only” Toggle-plus-caption blocks with `SettingsToggleRow`, preserving the current `$viewModel` bindings and existing descriptions:

```swift
SettingsToggleRow(
    title: "Freeze Cursor During Gesture",
    description: existingFreezeCursorDescription,
    isOn: $viewModel.freezeCursor
)

SettingsToggleRow(
    title: "Bottom Quarter Only",
    description: existingBottomQuarterDescription,
    isOn: $viewModel.bottomQuarterOnly
)
.padding(.top, 8)
```

Use the actual existing property names and description strings from the file.

**Step 2: Replace the Gesture toggle block**

Replace “Fine Control” and its caption with `SettingsToggleRow`, preserving the current binding and description:

```swift
SettingsToggleRow(
    title: "Fine Control",
    description: existingFineControlDescription,
    isOn: $viewModel.fineControl
)
```

Use the actual existing property name and description string from the file.

**Step 3: Compile all migrations**

Run: `swift build`
Expected: `Build complete!` with no compiler errors.

**Step 4: Commit**

```bash
git add Sources/Ledge/BehaviorSettingsTab.swift Sources/Ledge/GestureSettingsTab.swift
git commit -m "refactor(ui): align settings switches to trailing edge"
```

### Task 4: Verify release build and scope

**Files:**
- Verify: `Sources/Ledge/SettingsToggleRow.swift`
- Verify: `Sources/Ledge/SettingsView.swift`
- Verify: `Sources/Ledge/BehaviorSettingsTab.swift`
- Verify: `Sources/Ledge/GestureSettingsTab.swift`
- Verify unchanged sizing: `Sources/Ledge/SettingsWindow.swift`

**Step 1: Verify both size declarations**

Run:

```bash
rg 'width: 900, height: 650|width: 680, height: 500' Sources/Ledge/SettingsView.swift Sources/Ledge/SettingsWindow.swift
```

Expected: two 900×650 matches and no 680×500 match.

**Step 2: Verify all switches share the new row**

Run:

```bash
rg 'SettingsToggleRow|Toggle\(' Sources/Ledge/SettingsView.swift Sources/Ledge/BehaviorSettingsTab.swift Sources/Ledge/GestureSettingsTab.swift Sources/Ledge/SettingsToggleRow.swift
```

Expected: five `SettingsToggleRow` usages in the three tabs; the only direct settings switch is inside `SettingsToggleRow.swift`.

**Step 3: Build the release app binary**

Run: `swift build -c release`
Expected: `Build complete!` with no compiler errors.

**Step 4: Inspect the final diff**

Run: `git diff HEAD~3 --check && git diff HEAD~3 --stat`
Expected: no whitespace errors and only the new component plus the three settings files are changed by implementation commits.

**Step 5: Confirm no behavioral changes**

Review all five call sites and confirm they retain the same `Binding<Bool>` values. Confirm `SettingsWindow.swift`, `SettingsViewModel`, and preference persistence code are unchanged.
