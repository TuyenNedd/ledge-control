import AppKit
import Foundation
import LedgeCore

/// A live readout of everything the adapter layer cannot prove about itself.
///
/// **This window is the verification strategy for a layer that was written blind.** Nothing under
/// `Sources/Ledge/` has ever been compiled or run by its author — no macOS, no AppKit, no Apple
/// hardware — so every assumption it makes is an assumption. This is where each one becomes
/// visible in a glance instead of requiring a debugger:
///
/// - **Total events / gesture frames / touch count / raw ids** answer on-device checklist item 1:
///   does a `CGEvent` tap actually deliver single-finger trackpad touches? Three failures look
///   identical from outside — the tap delivering nothing, the tap delivering everything except
///   gesture events, and gesture events arriving without touch data — and the first two are only
///   distinguishable because the tap subscribes to all event types and counts them separately from
///   gesture frames.
/// - **Raw touch ids** are here because `LedgeCore` matches fingers between frames by
///   `NSTouch.identity.hash`, and nothing verifies that hash is stable for the life of a finger. If
///   it is not, arming and stepping both break in a way no unit test can see. Ids that change while
///   one finger stays down is the symptom.
/// - **Volume scalar** answers checklist item 3: whether `.shift` + `.option` on a synthesised
///   media key really buys 64 sub-steps, or is quietly ignored.
/// - **DisplayServices resolved** distinguishes "the private symbols are gone" from "brightness is
///   broken".
///
/// Refreshed by polling rather than by notification, because polling cannot itself fail to fire
/// and this window's entire job is to be trustworthy when something else is not.
final class DiagnosticsWindow: NSObject, NSWindowDelegate {
    private let controller: GestureController
    private let window: NSWindow
    private let readout: NSTextField
    private var timer: Timer?

    private static let refreshInterval: TimeInterval = 0.1

    init(controller: GestureController) {
        self.controller = controller

        let contentFrame = NSRect(x: 0, y: 0, width: 460, height: 380)
        window = NSWindow(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The wrapping variant rather than `labelWithString:` because this readout is inherently
        // multi-line, and it stays selectable so the whole thing can be copied into a bug report.
        readout = NSTextField(wrappingLabelWithString: "")
        super.init()

        window.title = "Ledge Diagnostics"
        // Closing must not deallocate the window, because the menu can reopen it.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        readout.frame = contentFrame.insetBy(dx: 16, dy: 16)
        readout.autoresizingMask = [.width, .height]
        readout.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        readout.maximumNumberOfLines = 0
        readout.alignment = .left
        window.contentView?.addSubview(readout)
    }

    deinit {
        stopRefreshing()
    }

    func show() {
        refresh()
        window.makeKeyAndOrderFront(nil)
        // Required because the app is an `.accessory`: without this the window can appear behind
        // whatever the user was looking at. The no-argument form, rather than the
        // `ignoringOtherApps:` one deprecated in macOS 14.
        NSApp.activate()
        startRefreshing()
    }

    func windowWillClose(_ notification: Notification) {
        stopRefreshing()
    }

    private func startRefreshing() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // `.common` so the readout keeps updating while a menu is open or a window is being
        // dragged — the moments when something is most likely being investigated.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let frame = controller.lastFrame
        let touches = frame?.touches ?? []

        var lines: [String] = []
        lines.append("Accessibility trusted   \(yesNo(Permissions.isTrusted()))")
        lines.append("Event tap enabled       \(yesNo(controller.isTapEnabled))")
        lines.append("Events seen (all types) \(controller.eventCount)")
        lines.append("Gesture frames seen     \(controller.frameCount)")
        lines.append("Steps emitted           \(controller.stepCount)")
        lines.append("")
        lines.append("Touch count             \(touches.count)")
        lines.append("Raw touch ids           \(touches.isEmpty ? "—" : touches.map { String($0.id) }.joined(separator: ", "))")
        lines.append("Last position           \(describe(touches.first?.position))")
        lines.append("Frame timestamp         \(describe(seconds: frame?.timestamp))")
        lines.append("")
        lines.append("Engine                  \(describeEngine())")
        lines.append("")
        lines.append("Cursor locked           \(yesNo(controller.isCursorLocked))")
        lines.append("")
        lines.append("Volume backend          \(controller.isUsingCoreAudioVolume ? "CoreAudio (no HUD)" : "synthesised media keys")")
        lines.append("Volume scalar           \(describe(unit: controller.currentVolumeScalar()))")
        lines.append("DisplayServices         \(controller.isBrightnessAvailable ? "resolved" : "NOT RESOLVED")")
        lines.append("Brightness              \(describe(unit: controller.currentBrightness()))")
        lines.append("")
        lines.append("What to look for:")
        lines.append("• Move the pointer and rest one finger on the trackpad. The tap")
        lines.append("  subscribes to every event type, so these three counters tell")
        lines.append("  three different failures apart:")
        lines.append("  – Events seen 0 → the tap is delivering nothing at all. The")
        lines.append("    problem is permission or tapCreate, not gestures. Quit, run")
        lines.append("    `make reset-permission`, relaunch and grant again — an ad-hoc")
        lines.append("    signature loses the grant on every rebuild while still")
        lines.append("    appearing enabled in Privacy & Security.")
        lines.append("  – Events climbing, gesture frames 0 → the tap works, but type 29")
        lines.append("    never arrives. The public route is dead and MultitouchSupport")
        lines.append("    is the remaining option.")
        lines.append("  – Gesture frames climbing, touch count 0 → gesture events arrive")
        lines.append("    without touch data attached.")
        lines.append("• Raw ids must stay constant while a finger stays down. They are")
        lines.append("  not guaranteed unique over time: once a finger lifts, a later")
        lines.append("  finger could in principle be given the same id.")
        lines.append("• Touch count must fall back to 0 when you lift your finger.")
        lines.append("• Volume steps of ~1.6% mean fine control works; ~6.25% means")
        lines.append("  the Shift+Option flags are being ignored.")

        readout.stringValue = lines.joined(separator: "\n")
    }

    private func describeEngine() -> String {
        guard let edge = controller.engagedEdge,
              let action = controller.engagedAction else { return "idle" }
        return "engaged — \(edge) — \(action.displayName)"
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private func describe(_ point: NormalizedPoint?) -> String {
        guard let point else { return "—" }
        return String(format: "x %.4f   y %.4f", point.x, point.y)
    }

    private func describe(seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%.3f s since boot", seconds)
    }

    private func describe(unit value: Float?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.4f  (%.2f%%)", value, value * 100)
    }
}
