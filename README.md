# Ledge

Slide along the edge of your MacBook trackpad to change volume and brightness.

Right edge for volume, left edge for brightness, one haptic pulse per step. Lives in the
menu bar, no configuration.

> **Status: unverified on device.** `LedgeCore` (all the gesture logic) is built and unit
> tested. Everything in `Sources/Ledge/` — the event tap, the system API calls, the menu bar —
> was written without access to macOS and has never been compiled. See
> [Verification status](#verification-status).

Built for macOS 26 Tahoe on Apple Silicon, built-in display only.

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture and the two OS findings that shaped it
- [`docs/PLAN.md`](docs/PLAN.md) — implementation plan and on-device verification checklist
