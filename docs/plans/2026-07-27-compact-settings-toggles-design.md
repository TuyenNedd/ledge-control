# Compact Settings Toggles Design

## Goal

Make the settings toggles feel closer to macOS System Settings without shrinking the settings window or changing toggle behavior.

## Constraints

- Keep the SwiftUI root view and initial `NSWindow` content size at 900×650.
- Keep the window resizable so the green traffic-light button continues to work.
- Preserve every existing binding and preference side effect.
- Use native SwiftUI controls rather than drawing a custom switch.

## Chosen design

Add one reusable `SettingsToggleRow` for all five settings toggles. Each row uses a full-width horizontal layout with a leading title and description, flexible spacing, and a trailing label-hidden native switch. The switch uses `.toggleStyle(.switch)` and `.controlSize(.small)` for compact macOS-native metrics.

Replace the duplicated toggle-plus-caption markup in General, Behavior, and Gesture settings with this row while retaining their existing bindings. Restore the unintended local `SettingsView` frame change from 680×500 to 900×650; leave the native 900×650 window and its resizable style unchanged.

## Alternatives considered

1. Add only `.controlSize(.small)` to each current toggle. This is the smallest code change, but it leaves switches immediately beside labels rather than trailing-aligned like System Settings.
2. Draw a custom mini switch. This offers exact sizing but loses native behavior and appearance and adds unnecessary maintenance.
3. Use a reusable native row. This gives consistent macOS-style alignment, avoids duplication, and preserves accessibility and platform behavior. This is the selected approach.

## Behavior and data flow

`SettingsToggleRow` receives a `Binding<Bool>`. User interaction updates the same existing bindings, so `SettingsViewModel` continues to persist preferences, apply gesture changes, and handle launch-at-login failures exactly as before. The component adds no state or side effects.

## Accessibility and error handling

The switch retains the title as its accessibility label even though the visible switch label is hidden. Existing model-level error handling remains unchanged, including restoring Launch at Login state if registration fails.

## Verification

- Confirm both window sizing declarations remain 900×650.
- Confirm all five switches use the shared compact row.
- Build the Swift package in debug and release configurations.
- Review the diff to ensure no preference logic or unrelated UI changed.
