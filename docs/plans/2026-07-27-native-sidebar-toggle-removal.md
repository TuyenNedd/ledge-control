# Native Sidebar Toggle Removal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore the native full-height macOS Settings sidebar while removing only its system Show/Hide Sidebar toolbar item.

**Architecture:** `SettingsView` returns to a native balanced `NavigationSplitView`. `SettingsWindow` performs narrowly scoped AppKit cleanup after SwiftUI realizes its toolbar and observes that toolbar for later item additions, removing only `NSToolbarItem.Identifier.toggleSidebar`.

**Tech Stack:** SwiftUI, AppKit, Swift Package Manager, macOS 14+

---

### Task 1: Restore the native split-view layout

**Files:**
- Modify: `Sources/Ledge/SettingsView.swift:6-60`

**Step 1:** Replace the fixed `HStack`, 200pt frame, and explicit divider with the previous two-column `NavigationSplitView`.

**Step 2:** Restore `.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)` and `.navigationSplitViewStyle(.balanced)`.

**Step 3:** Do not restore `.toolbar(removing: .sidebarToggle)` because removal moves to AppKit.

**Step 4:** Confirm the root remains `.frame(width: 900, height: 650)` and all selection/detail code is unchanged.

### Task 2: Remove only the native sidebar toggle

**Files:**
- Modify: `Sources/Ledge/SettingsWindow.swift:14-90`

**Step 1:** Add observer storage for `NSToolbar.didAddItemNotification`.

**Step 2:** After `makeKeyAndOrderFront`, schedule a main-run-loop cleanup that discovers the window toolbar, installs a scoped observer if needed, and removes every item whose identifier equals `.toggleSidebar`.

**Step 3:** If the observer sees an item added to the scoped toolbar, schedule the same cleanup on the next main-run-loop turn rather than mutating the toolbar inside its notification.

**Step 4:** Remove the observer in `windowWillClose` and before replacing it with an observer for a different toolbar.

### Task 3: Verify and deliver

**Files:**
- Verify: `Sources/Ledge/SettingsView.swift`
- Verify: `Sources/Ledge/SettingsWindow.swift`
- Verify unchanged: `Sources/Ledge/SettingsToggleRow.swift`

**Step 1:** Run `git diff --check`.

**Step 2:** Run `swift build` and `swift build -c release`.

**Step 3:** Search for `NavigationSplitView`, `.toggleSidebar`, dimensions, and any remaining `.toolbar(removing:)` usage.

**Step 4:** Request an independent source review focused on toolbar lifecycle, observer cleanup, and native layout preservation.

**Step 5:** Commit the two source files and plan documents, push `feat/phase-3-ui-overhaul`, and verify local/remote commit hashes match.
