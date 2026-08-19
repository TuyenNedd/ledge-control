# Ledge -- Design Document

## Problem

macOS changes volume and brightness in coarse steps (16 for volume). Finer steps exist
via `Shift`+`Option`+media key, but pressing three keys at once is awkward -- especially
when reclining and watching something.

Goal: adjust volume and brightness by sliding a finger along the **edge of the trackpad**,
with fine granularity and no configuration required.

## Target environment

This is built for one specific machine. Decisions below are made for it and are not
intended to be portable.

| | |
|---|---|
| Machine | MacBook Pro M4 (Apple Silicon) |
| OS | macOS 26.2 (Tahoe) |
| Displays | Built-in only -- external display support is explicitly out of scope |
| Toolchain | Xcode installed, SwiftPM, no paid Apple Developer account |

## Two findings that shaped the architecture

### 1. `OSDUIHelper` no longer exists on Tahoe

Prior art (MonitorControl, SlimHUD, NewBezelServices) invokes the native volume/brightness
HUD by talking to the `com.apple.OSDUIHelper` XPC service. On macOS 26 that process is gone,
confirmed by Apple DTS in
[developer forums thread 804054](https://developer.apple.com/forums/thread/804054), where
the engineer also notes that the name, location, and behaviour of system processes are
implementation details and building on them invites breakage.

**Consequence:** we cannot summon the HUD directly. To get a native HUD we must cause the
change through a path the OS itself already decorates with a HUD.

### 2. Synthesised brightness media keys do not change brightness, but they do trigger the native indicator

Posting a `systemDefined` event with `NX_KEYTYPE_SOUND_UP` reliably changes volume and
brings up the system HUD. The brightness equivalents behave differently -- see
[developer forums thread 60545](https://developer.apple.com/forums/thread/60545), where
volume keys work but `NX_KEYTYPE_BRIGHTNESS_UP`/`DOWN` do not change the brightness value.

However, while synthesised brightness keys do not perform the actual brightness change, they
**do** trigger the native HUD indicator to display the current brightness level. This means
the approach for brightness is:

1. `DisplayServices` sets the brightness value directly.
2. A synthesised brightness media key event is posted immediately after.
3. The media key triggers the native HUD, which reads and displays the already-updated value.

This gives native HUD display for brightness without a custom overlay.

**Consequence:** volume and brightness still use different backends for the actual change, but
both get native HUD display -- volume through the media key doing the change, brightness through
`DisplayServices` doing the change followed by a media key triggering the indicator.

## Architecture

Two layers, split by testability:

```
+------------------------------- LedgeCore (pure Swift, cross-platform) ------------------------+
|  TouchFrame  ->  GestureEngine  ->  [GestureEvent]                                           |
|                                                                                              |
|  No AppKit, no system calls. Fully unit tested, including on Linux.                          |
+----------------------------------------------------------------------------------------------+
                                          ^                    |
                                   touch frames           gesture events
                                          |                    v
+------------------------------- Ledge (macOS only, thin adapters) -----------------------------+
|  EventTapTouchSource  -->  GestureController  -->  VolumeController / BrightnessController    |
|                                    |                                                         |
|                                    +-->  MenuBarController, DiagnosticsWindow                 |
+----------------------------------------------------------------------------------------------+
```

The split is deliberate: **all decision logic lives in `LedgeCore` where it can be tested**,
and the macOS layer contains only I/O adapters with no branching logic worth testing. This
matters here more than usual, because the gesture tuning logic is the part most likely to
need iteration, and the system-API layer is the part that cannot be tested in CI at all.

### Input: reading finger position on the trackpad

`CGEvent.tapCreate` with a mask covering event type `29` (`NSEventTypeGesture`), converted
via `NSEvent(cgEvent:)` and read with `allTouches()`. Each `NSTouch` provides
`normalizedPosition` in the range 0...1 with origin at the **lower left** of the trackpad.

This is public API. It requires Accessibility permission.

Rejected alternative: the private `MultitouchSupport.framework`, which many trackpad apps
use. Its `MTTouch` struct layout has changed between macOS releases, and a wrong layout
means reading garbage or crashing. Since this code cannot be compiled or tested in the
development sandbox, an untestable private struct layout is an unacceptable risk. The
`TouchSource` protocol leaves the door open if the event tap turns out to be insufficient.

### Output: volume

`MediaKeySender` posts a `systemDefined` `NSEvent` (subtype 8, `NX_SUBTYPE_AUX_CONTROL_BUTTONS`)
with `NX_KEYTYPE_SOUND_UP` / `NX_KEYTYPE_SOUND_DOWN`, and `.shift`+`.option` modifier flags
when fine mode is on.

Why this and not CoreAudio: **it is the only remaining way to get a native HUD on Tahoe.**
The OS performs the change itself, so it draws its own indicator. Zero private API.

`CoreAudioVolumeController` exists as a selectable fallback. It gives genuinely continuous
control but produces no HUD, so it is not the default.

### Output: brightness

`DisplayServicesBrightnessController` resolves symbols from
`/System/Library/PrivateFrameworks/DisplayServices.framework` at runtime via `dlopen`/`dlsym`:

- `DisplayServicesGetBrightness`
- `DisplayServicesSetBrightness`

After setting the brightness value, the controller posts a synthesised brightness media key
event (`NX_KEYTYPE_BRIGHTNESS_UP` or `NX_KEYTYPE_BRIGHTNESS_DOWN`). While this key does not
change the brightness (that was already done by `DisplayServices`), it triggers the native
HUD indicator to display the current brightness level.

Loading by `dlsym` rather than linking means a missing symbol on a future macOS degrades to
"brightness disabled, volume still works" instead of a launch failure.

This is a private API. It is the accepted cost: `IODisplaySetFloatParameter` does not work
for the built-in display on Apple Silicon, and synthesised brightness keys alone do not
change the value. Documented as the primary compatibility risk.

### Cursor freeze

When the "Freeze Cursor During Gesture" preference is enabled and a gesture is active, the
event tap captures the cursor position at engagement and then warps the cursor back to that
saved position on every `mouseMoved` event using `CGWarpMouseCursorPosition`. The event is
also swallowed (returning nil from the tap callback) so that downstream consumers never see
the movement.

On disengage, the warp-back stops and cursor movement resumes normally.

**Rejected approaches:**

- **Returning nil for mouseMoved without warping:** The event tap can suppress events from
  reaching other processes, but the window server has already moved the cursor by the time the
  tap callback fires. Returning nil prevents apps from seeing the move but does not undo it.
  The cursor still drifts.

- **`CGAssociateMouseAndMouseCursorPosition(false)`:** This API is documented to disconnect
  the cursor from mouse movement. On macOS 26 Tahoe it has no observable effect -- the cursor
  continues to move regardless of the association state. This may be a regression or a
  deliberate deprecation; either way it cannot be relied upon.

The warp-per-event approach has a minor visual artifact: the cursor may flicker by one pixel
on each event before being warped back. In practice this is not perceptible at normal frame
rates.

### Gesture engine

A state machine over touch frames:

```
idle --touch starts inside edge band--> armed --vertical travel > activationDistance--> engaged
  ^                                       |                                             |
  +---------------------------------------+---------------------------------------------+
                    finger lifts / drifts out of band / second finger / typing
```

While `engaged`, an anchor tracks the last position that produced a step. Each time travel
from the anchor exceeds `stepDistance`, one step is emitted and the anchor advances by
exactly that distance. Anchoring rather than accumulating deltas prevents rounding drift
over a long slide.

**The guards are the actual product.** Reading a finger position is easy; not firing when
the user did not mean it is the hard part. The trackpad edge is territory fingers cross
constantly while scrolling and typing.

| Guard | Rationale |
|---|---|
| Touch must *start* inside the edge band | A finger that drifts in mid-scroll is not a deliberate gesture |
| Exactly one touch | Two-finger scrolling passes over the edge all the time |
| Vertical travel must exceed `activationDistance` before engaging | Dead zone; a tap or a small wobble does nothing |
| At activation, `|dy|` must exceed `|dx|` | Rejects horizontal swipes that begin at the edge |
| Disengage if the finger leaves the band plus tolerance | The user has moved on to something else |
| Typing lockout | Ignore gestures within `typingLockout` seconds of a keystroke |
| Frame gap timeout | A stale gesture must not resume after a pause |
| Optional bottom-quarter restriction | Off by default; available if false positives persist |

Slidr's own changelog is instructive: v1.0 shipped the gesture, and bottom-quarter mode,
typing detection, cursor freeze, and modifier keys arrived across v1.1-v1.3. Those are not
features, they are false-positive fixes discovered in use. Shipping them in v1 is the single
highest-value thing this design can borrow.

### Step granularity

`stepDistance` defaults to `0.016` of trackpad height, approximately one full-height slide per
64 steps, matching the 64 sub-steps that fine volume mode provides. With fine mode off, the
effective distance is multiplied by 4 to match the OS's 16 coarse steps, so a full slide still
spans the whole range.

## Non-goals

- External display brightness (DDC) -- the user has no external display
- Mac App Store distribution -- impossible with private API, and not wanted
- Configuration UI beyond a menu -- the entire premise is that it works without setup
- Haptic feedback -- explored and removed. Neither `NSHapticFeedbackManager` (does not work
  for LSUIElement apps) nor `MTActuator` (private API) provided reliable results for an
  accessory app. Feature was dropped by user decision

## Risks

| Risk | Severity | Status |
|---|---|---|
| Gesture events from the tap may not carry single-finger touches | **High** | **Resolved** -- confirmed working on device |
| `.shift`+`.option` flags may be ignored on synthesised events, leaving coarse steps | Medium | **Resolved** -- fine mode works |
| `DisplayServices` symbols may change or vanish | Medium | Mitigated by `dlsym` with graceful degradation |
| Brightness HUD may not appear | Medium | **Resolved** -- synthesised media key after DisplayServices change triggers the native HUD |
| Ad-hoc signature changes on rebuild can reset Accessibility permission | Low | Mitigated by stable bundle identifier; documented in README |

## Verification status

**The app has been compiled and verified on macOS 26.2 Tahoe.** `LedgeCore` is fully built and
tested (54 unit tests passing on both Linux and macOS). The macOS adapter layer
(`Sources/Ledge/`) has been compiled, run, and exercised on-device. Volume, brightness, cursor
freeze, and gesture recognition are all confirmed working.
