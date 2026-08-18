import AppKit

/// A custom brightness indicator overlay that replaces the system HUD.
///
/// `DisplayServicesBrightnessChanged` no longer triggers the system brightness indicator on
/// macOS 26 Tahoe (the OSDUIHelper XPC service is gone). This panel provides visual feedback
/// in the same spirit: a dark rounded rect with a sun icon and a progress bar, shown for 1.5
/// seconds then faded out.
///
/// Styled as a borderless `NSPanel` at just below `.screenSaver` level so it floats above
/// everything without stealing focus or interfering with full-screen apps.
final class BrightnessHUD {
    private let panel: NSPanel
    private let iconView: NSImageView
    private let progressBar: NSView
    private let progressFill: NSView
    private let backgroundView: NSVisualEffectView

    /// How many times the HUD has been shown since launch. Diagnostics only.
    private(set) var showCount: Int = 0

    private var hideTimer: Timer?

    /// Width of the HUD panel.
    private static let hudWidth: CGFloat = 200
    /// Height of the HUD panel.
    private static let hudHeight: CGFloat = 60
    /// How long the HUD stays visible before fading out.
    private static let displayDuration: TimeInterval = 1.5
    /// Fade-out animation duration.
    private static let fadeDuration: TimeInterval = 0.3

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: Self.hudWidth, height: Self.hudHeight)

        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        // Dark rounded-rect background with vibrancy
        backgroundView = NSVisualEffectView(frame: contentRect)
        backgroundView.material = .hudWindow
        backgroundView.state = .active
        backgroundView.blendingMode = .behindWindow
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 14
        backgroundView.layer?.masksToBounds = true
        panel.contentView = backgroundView

        // Sun icon (SF Symbol)
        let iconSize: CGFloat = 24
        let iconFrame = NSRect(x: 16, y: (Self.hudHeight - iconSize) / 2, width: iconSize, height: iconSize)
        iconView = NSImageView(frame: iconFrame)
        if let sunImage = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            iconView.image = sunImage.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .white
        backgroundView.addSubview(iconView)

        // Progress bar track
        let barX: CGFloat = 50
        let barWidth: CGFloat = Self.hudWidth - barX - 16
        let barHeight: CGFloat = 6
        let barY: CGFloat = (Self.hudHeight - barHeight) / 2
        let barFrame = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)

        progressBar = NSView(frame: barFrame)
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        progressBar.layer?.cornerRadius = barHeight / 2
        backgroundView.addSubview(progressBar)

        // Progress bar fill
        progressFill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: barHeight))
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor.white.cgColor
        progressFill.layer?.cornerRadius = barHeight / 2
        progressBar.addSubview(progressFill)
    }

    /// Show (or refresh) the HUD with the given brightness level (0...1).
    func show(brightness: Float) {
        showCount += 1
        positionOnScreen()
        updateProgress(CGFloat(brightness.clamped(to: 0...1)))

        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.displayDuration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    private func updateProgress(_ fraction: CGFloat) {
        let barWidth = progressBar.bounds.width
        let fillWidth = barWidth * fraction
        progressFill.frame = NSRect(
            x: 0,
            y: 0,
            width: fillWidth,
            height: progressBar.bounds.height
        )
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - Self.hudWidth / 2
        // Position near the bottom center, similar to system HUD placement
        let y = screenFrame.origin.y + 140
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
