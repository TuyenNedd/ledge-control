# Native Sidebar Toggle Removal Design

## Goal

Preserve the native macOS `NavigationSplitView` sidebar appearance—including full-height sidebar material and traffic lights over the sidebar—while removing only the system Show/Hide Sidebar toolbar item.

## Constraints

- Keep the Settings root and native window at 900×650.
- Keep the window resizable and preserve Cmd+W and all traffic-light behavior.
- Preserve the existing sidebar sections, selection state, detail views, and native 180/200/220-point column sizing.
- Keep the compact full-width settings toggle rows unchanged.
- Do not replace or hide the complete toolbar/titlebar.

## Chosen design

Restore the prior native two-column `NavigationSplitView` in `SettingsView`, including its sidebar `List`, balanced split-view style, and native column sizing. Remove the ineffective SwiftUI `.toolbar(removing: .sidebarToggle)` modifier.

After `SettingsWindow` presents the hosting controller, AppKit inspects the realized `NSToolbar` and removes only items whose public identifier is `NSToolbarItem.Identifier.toggleSidebar`. A presentation-scoped `NSToolbar.willAddItemNotification` observer is installed before the window is shown because SwiftUI creates and reconciles the toolbar lazily. Its callback schedules cleanup on the next main run-loop, after the pending insertion completes. The observer is removed and queued work invalidated when the window closes.

## Alternatives considered

1. Keep `.toolbar(removing: .sidebarToggle)`. This has already failed on the user's macOS runtime.
2. Replace `NavigationSplitView` with an `HStack`. This guarantees no toggle but loses the native full-height sidebar appearance requested by the user.
3. Hide or replace the entire toolbar. This risks breaking the transparent titlebar, traffic lights, and future native items.
4. Restore the native split view and remove only `.toggleSidebar` through AppKit. This preserves the desired UI and targets only the unwanted item, so it is selected.

## Lifecycle and safety

`SettingsWindow` is retained and reopened rather than recreated. Before each presentation it installs a lifecycle-scoped `NSToolbar.willAddItemNotification` observer, then schedules toolbar cleanup after `makeKeyAndOrderFront`. The cleanup uses the public item identifier rather than localized labels or private view traversal. The notification callback filters to the Settings toolbar and dispatches cleanup to the next run-loop turn so it does not mutate the toolbar during its pre-add notification. A presentation generation token invalidates queued cleanup when the window closes.

## Verification

- Confirm `SettingsView` uses `NavigationSplitView` and no fixed root `HStack`.
- Confirm no SwiftUI `.toolbar(removing: .sidebarToggle)` remains.
- Confirm AppKit removal compares only against `.toggleSidebar`.
- Confirm both Settings dimensions remain 900×650.
- Run debug and release builds, diff checks, and independent source review.
