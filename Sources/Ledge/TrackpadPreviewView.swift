import SwiftUI
import LedgeCore

/// An interactive 4-edge trackpad preview with draggable edge bands and action pickers.
///
/// Shows a dark rounded rectangle representing the trackpad surface with thin colored bands
/// flush against all four inner edges. Each band is:
/// - Draggable to resize its width
/// - Clickable to toggle enable/disable
/// - Colored blue when enabled (opacity 0.3), grayed out when disabled (opacity 0.15)
/// - Rendered with rounded ends for a polished appearance
///
/// Layout matches the Figma design: landscape-oriented dark trackpad body with a subtle border,
/// edge bands as thin colored strips sitting directly on the inner edges with rounded corners.
///
/// Action pickers are positioned OUTSIDE the trackpad shape: top dropdown above, bottom below,
/// left to the left, right to the right.
struct InteractiveTrackpadPreview: View {
    @Binding var leftEdge: EdgeConfig
    @Binding var rightEdge: EdgeConfig
    @Binding var topEdge: EdgeConfig
    @Binding var bottomEdge: EdgeConfig

    /// Which edge is currently engaged (for live feedback during gestures). Optional.
    var engagedEdge: TrackpadEdge?

    /// Corner radius for the trackpad shape.
    private let trackpadCornerRadius: CGFloat = 18

    /// Inset from the trackpad border where edge bands are drawn.
    private let bandInset: CGFloat = 3

    /// Corner radius for edge band capsules.
    private let bandCornerRadius: CGFloat = 4

    var body: some View {
        VStack(spacing: 8) {
            // Top edge controls (above trackpad)
            edgeControlRow(edge: .top, config: $topEdge)

            HStack(spacing: 8) {
                // Left edge controls (to the left of trackpad)
                edgeControlColumn(edge: .left, config: $leftEdge)

                // The trackpad surface
                trackpadView
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)

                // Right edge controls (to the right of trackpad)
                edgeControlColumn(edge: .right, config: $rightEdge)
            }

            // Bottom edge controls (below trackpad)
            edgeControlRow(edge: .bottom, config: $bottomEdge)
        }
    }

    // MARK: - Trackpad Surface

    private var trackpadView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Dark trackpad background with subtle border (Figma style)
                RoundedRectangle(cornerRadius: trackpadCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: trackpadCornerRadius)
                            .strokeBorder(Color.gray.opacity(0.35), lineWidth: 1.5)
                    )

                // Left edge band - thin vertical strip flush on left inner edge
                edgeBand(
                    edge: .left,
                    config: $leftEdge,
                    parentWidth: width,
                    parentHeight: height
                )

                // Right edge band - thin vertical strip flush on right inner edge
                edgeBand(
                    edge: .right,
                    config: $rightEdge,
                    parentWidth: width,
                    parentHeight: height
                )

                // Top edge band - thin horizontal strip flush on top inner edge
                edgeBand(
                    edge: .top,
                    config: $topEdge,
                    parentWidth: width,
                    parentHeight: height
                )

                // Bottom edge band - thin horizontal strip flush on bottom inner edge
                edgeBand(
                    edge: .bottom,
                    config: $bottomEdge,
                    parentWidth: width,
                    parentHeight: height
                )
            }
        }
    }

    // MARK: - Edge Band View

    /// A single edge band overlay within the trackpad as a thin rounded strip flush against the edge.
    @ViewBuilder
    private func edgeBand(
        edge: TrackpadEdge,
        config: Binding<EdgeConfig>,
        parentWidth: CGFloat,
        parentHeight: CGFloat
    ) -> some View {
        let isActive = engagedEdge == edge
        let bandColor = bandColorFor(config: config.wrappedValue, isActive: isActive)

        switch edge {
        case .left:
            let bandPixelWidth = max(CGFloat(config.wrappedValue.bandWidth) * parentWidth, 6)
            // Vertical strip on the left inner edge, inset from top/bottom
            let bandHeight = parentHeight - (bandInset * 2) - (trackpadCornerRadius * 0.6)
            RoundedRectangle(cornerRadius: bandCornerRadius)
                .fill(bandColor)
                .frame(width: bandPixelWidth, height: bandHeight)
                .position(x: bandInset + bandPixelWidth / 2, y: parentHeight / 2)
                .gesture(dragGestureHorizontal(config: config, parentWidth: parentWidth, fromLeft: true))
                .onTapGesture { config.wrappedValue.isEnabled.toggle() }

        case .right:
            let bandPixelWidth = max(CGFloat(config.wrappedValue.bandWidth) * parentWidth, 6)
            // Vertical strip on the right inner edge, inset from top/bottom
            let bandHeight = parentHeight - (bandInset * 2) - (trackpadCornerRadius * 0.6)
            RoundedRectangle(cornerRadius: bandCornerRadius)
                .fill(bandColor)
                .frame(width: bandPixelWidth, height: bandHeight)
                .position(x: parentWidth - bandInset - bandPixelWidth / 2, y: parentHeight / 2)
                .gesture(dragGestureHorizontal(config: config, parentWidth: parentWidth, fromLeft: false))
                .onTapGesture { config.wrappedValue.isEnabled.toggle() }

        case .top:
            let bandPixelHeight = max(CGFloat(config.wrappedValue.bandWidth) * parentHeight, 6)
            // Horizontal strip on the top inner edge, inset from left/right
            let bandWidth = parentWidth - (bandInset * 2) - (trackpadCornerRadius * 0.6)
            RoundedRectangle(cornerRadius: bandCornerRadius)
                .fill(bandColor)
                .frame(width: bandWidth, height: bandPixelHeight)
                .position(x: parentWidth / 2, y: bandInset + bandPixelHeight / 2)
                .gesture(dragGestureVertical(config: config, parentHeight: parentHeight, fromTop: true))
                .onTapGesture { config.wrappedValue.isEnabled.toggle() }

        case .bottom:
            let bandPixelHeight = max(CGFloat(config.wrappedValue.bandWidth) * parentHeight, 6)
            // Horizontal strip on the bottom inner edge, inset from left/right
            let bandWidth = parentWidth - (bandInset * 2) - (trackpadCornerRadius * 0.6)
            RoundedRectangle(cornerRadius: bandCornerRadius)
                .fill(bandColor)
                .frame(width: bandWidth, height: bandPixelHeight)
                .position(x: parentWidth / 2, y: parentHeight - bandInset - bandPixelHeight / 2)
                .gesture(dragGestureVertical(config: config, parentHeight: parentHeight, fromTop: false))
                .onTapGesture { config.wrappedValue.isEnabled.toggle() }
        }
    }

    /// Compute band color based on enabled state and engagement.
    private func bandColorFor(config: EdgeConfig, isActive: Bool) -> Color {
        if !config.isEnabled {
            return Color.gray.opacity(0.15)
        }
        return isActive ? Color.blue.opacity(0.6) : Color.blue.opacity(0.3)
    }

    // MARK: - Drag Gestures

    /// Horizontal drag gesture for left/right edge band resizing.
    private func dragGestureHorizontal(
        config: Binding<EdgeConfig>,
        parentWidth: CGFloat,
        fromLeft: Bool
    ) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let deltaFraction: Double
                if fromLeft {
                    deltaFraction = Double(value.translation.width / parentWidth)
                } else {
                    deltaFraction = Double(-value.translation.width / parentWidth)
                }
                let newWidth = max(0.01, min(0.15, config.wrappedValue.bandWidth + deltaFraction * 0.1))
                config.wrappedValue.bandWidth = newWidth
            }
    }

    /// Vertical drag gesture for top/bottom edge band resizing.
    private func dragGestureVertical(
        config: Binding<EdgeConfig>,
        parentHeight: CGFloat,
        fromTop: Bool
    ) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let deltaFraction: Double
                if fromTop {
                    deltaFraction = Double(value.translation.height / parentHeight)
                } else {
                    deltaFraction = Double(-value.translation.height / parentHeight)
                }
                let newWidth = max(0.01, min(0.15, config.wrappedValue.bandWidth + deltaFraction * 0.1))
                config.wrappedValue.bandWidth = newWidth
            }
    }

    // MARK: - Edge Controls (Outside Trackpad)

    /// Horizontal row of controls for top/bottom edge (action picker + band width display).
    private func edgeControlRow(edge: TrackpadEdge, config: Binding<EdgeConfig>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: config.action) {
                ForEach(EdgeAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Text(bandWidthLabel(config.wrappedValue.bandWidth))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(config.wrappedValue.isEnabled ? .primary : .tertiary)
        }
        .opacity(config.wrappedValue.isEnabled ? 1.0 : 0.5)
    }

    /// Vertical column of controls for left/right edge (action picker + band width display).
    private func edgeControlColumn(edge: TrackpadEdge, config: Binding<EdgeConfig>) -> some View {
        VStack(spacing: 4) {
            Picker("", selection: config.action) {
                ForEach(EdgeAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Text(bandWidthLabel(config.wrappedValue.bandWidth))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(config.wrappedValue.isEnabled ? .primary : .tertiary)
        }
        .opacity(config.wrappedValue.isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Helpers

    /// Displays approximate mm value (1.0 fraction ~ 160mm trackpad width).
    private func bandWidthLabel(_ fraction: Double) -> String {
        let mm = fraction * 160.0
        return String(format: "%.1f mm", mm)
    }
}

// MARK: - Binding Extension for EdgeConfig

/// Convenience extension to create a Binding<EdgeAction> from a Binding<EdgeConfig>.
private extension Binding where Value == EdgeConfig {
    var action: Binding<EdgeAction> {
        Binding<EdgeAction>(
            get: { self.wrappedValue.action },
            set: { self.wrappedValue.action = $0 }
        )
    }

    var bandWidth: Binding<Double> {
        Binding<Double>(
            get: { self.wrappedValue.bandWidth },
            set: { self.wrappedValue.bandWidth = $0 }
        )
    }

    var isEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue.isEnabled },
            set: { self.wrappedValue.isEnabled = $0 }
        )
    }
}

// MARK: - Legacy TrackpadPreviewView (Onboarding Compatibility)

/// A simpler 2-edge preview used by onboarding, compatible with the old API shape.
///
/// Shows only left and right bands (no interactivity) for the "Try It" onboarding page.
/// This is kept separate from the interactive 4-edge preview to avoid breaking the onboarding
/// flow while providing the full interactive experience in Settings.
struct TrackpadPreviewView: View {
    @Binding var edgeBandWidth: Double
    var swapSides: Bool
    var engagedEdge: String?

    init(edgeBandWidth: Binding<Double>, swapSides: Bool, engagedEdge: String? = nil) {
        self._edgeBandWidth = edgeBandWidth
        self.swapSides = swapSides
        self.engagedEdge = engagedEdge
    }

    private var mmLabel: String {
        String(format: "%.1f mm", edgeBandWidth * 160.0)
    }

    private var leftBandActive: Bool { engagedEdge == "left" }
    private var rightBandActive: Bool { engagedEdge == "right" }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bandPixelWidth = max(CGFloat(edgeBandWidth) * width, 14)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1.5)
                    )

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(leftBandActive ? Color.blue.opacity(0.6) : Color.blue.opacity(0.2))
                        .frame(width: bandPixelWidth, height: height)
                        .animation(.easeInOut(duration: 0.2), value: leftBandActive)
                    Spacer()
                }

                HStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 0)
                        .fill(rightBandActive ? Color.blue.opacity(0.6) : Color.blue.opacity(0.2))
                        .frame(width: bandPixelWidth, height: height)
                        .animation(.easeInOut(duration: 0.2), value: rightBandActive)
                }

                Text(mmLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
    }
}
