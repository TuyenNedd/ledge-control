import SwiftUI
import LedgeCore

/// An interactive 4-edge trackpad preview with draggable edge bands and action pickers.
///
/// Layout matches the Figma design: a single large light-gray RoundedRectangle forms
/// the trackpad shape, with 4 straight rectangular bands positioned at the edges but
/// inset from the corners by the corner radius amount.
///
/// - Top band: shorter than full width, inset from left/right corners
/// - Bottom band: shorter than full width, inset from left/right corners
/// - Left band: shorter than full height, inset from top/bottom corners
/// - Right band: shorter than full height, inset from top/bottom corners
/// - Corners expose the light gray trackpad background (no bands overlap corners)
/// - No border/stroke on the trackpad body
/// - Bands sit flush against the outer edge of the trackpad, directed inward
/// - Band thickness ~20-22pt
///
/// Each band is:
/// - Draggable to resize its width
/// - Clickable to toggle enable/disable
/// - Colored blue when enabled (opacity 0.6), grayed out when disabled (opacity 0.15)
///
/// Action pickers are positioned OUTSIDE the frame: top dropdown above, bottom below,
/// left to the left, right to the right.
struct InteractiveTrackpadPreview: View {
    @Binding var leftEdge: EdgeConfig
    @Binding var rightEdge: EdgeConfig
    @Binding var topEdge: EdgeConfig
    @Binding var bottomEdge: EdgeConfig

    /// Which edge is currently engaged (for live feedback during gestures). Optional.
    var engagedEdge: TrackpadEdge?

    /// Corner radius for the trackpad body shape.
    private let trackpadCornerRadius: CGFloat = 14

    /// Default band thickness in points (visual size of the frame bands).
    private let defaultBandThickness: CGFloat = 23

    var body: some View {
        VStack(spacing: 8) {
            // Top edge controls (above trackpad)
            edgeControlRow(edge: .top, config: $topEdge)

            HStack(spacing: 8) {
                // Left edge controls (to the left of trackpad)
                edgeControlColumn(edge: .left, config: $leftEdge)

                // The trackpad surface with surrounding bands
                trackpadFrameView
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)

                // Right edge controls (to the right of trackpad)
                edgeControlColumn(edge: .right, config: $rightEdge)
            }

            // Bottom edge controls (below trackpad)
            edgeControlRow(edge: .bottom, config: $bottomEdge)
        }
    }

    // MARK: - Trackpad Frame View (Figma Layout)

    /// The composite view: a single large rounded rectangle background with 4 bands
    /// positioned at the edges, inset from corners so the gray background shows through.
    private var trackpadFrameView: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let totalHeight = geometry.size.height

            // Calculate band thicknesses (scaled by bandWidth fraction)
            let topThickness = bandThickness(for: topEdge, totalDimension: totalHeight)
            let bottomThickness = bandThickness(for: bottomEdge, totalDimension: totalHeight)
            let leftThickness = bandThickness(for: leftEdge, totalDimension: totalWidth)
            let rightThickness = bandThickness(for: rightEdge, totalDimension: totalWidth)

            // Corner radius inset: bands do not extend into the rounded corner area
            let cornerInset = trackpadCornerRadius

            ZStack(alignment: .topLeading) {
                // Background: single large light-gray rounded rectangle, no border
                // UNVERIFIED: nsColor usage
                RoundedRectangle(cornerRadius: trackpadCornerRadius)
                    .fill(Color.gray.opacity(0.12))

                // Top band: flush with top edge, inset from left/right by cornerInset
                topBandView(
                    totalWidth: totalWidth,
                    thickness: topThickness,
                    cornerInset: cornerInset
                )

                // Bottom band: flush with bottom edge, inset from left/right by cornerInset
                bottomBandView(
                    totalWidth: totalWidth,
                    totalHeight: totalHeight,
                    thickness: bottomThickness,
                    cornerInset: cornerInset
                )

                // Left band: flush with left edge, inset from top/bottom by cornerInset
                leftBandView(
                    totalHeight: totalHeight,
                    thickness: leftThickness,
                    cornerInset: cornerInset
                )

                // Right band: flush with right edge, inset from top/bottom by cornerInset
                rightBandView(
                    totalWidth: totalWidth,
                    totalHeight: totalHeight,
                    thickness: rightThickness,
                    cornerInset: cornerInset
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: trackpadCornerRadius))
        }
    }

    // MARK: - Individual Band Views (Inset from Corners)

    /// Top band: positioned at top edge, inset from left/right corners.
    private func topBandView(totalWidth: CGFloat, thickness: CGFloat, cornerInset: CGFloat) -> some View {
        let isActive = engagedEdge == .top
        let color = bandColorFor(config: topEdge, isActive: isActive)
        let bandWidth = totalWidth - cornerInset * 2

        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: bandWidth, height: thickness)
            .offset(x: cornerInset, y: 0)
            .gesture(dragGestureVertical(config: $topEdge, parentHeight: thickness, fromTop: true))
            .onTapGesture { topEdge.isEnabled.toggle() }
    }

    /// Bottom band: positioned at bottom edge, inset from left/right corners.
    private func bottomBandView(totalWidth: CGFloat, totalHeight: CGFloat, thickness: CGFloat, cornerInset: CGFloat) -> some View {
        let isActive = engagedEdge == .bottom
        let color = bandColorFor(config: bottomEdge, isActive: isActive)
        let bandWidth = totalWidth - cornerInset * 2

        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: bandWidth, height: thickness)
            .offset(x: cornerInset, y: totalHeight - thickness)
            .gesture(dragGestureVertical(config: $bottomEdge, parentHeight: thickness, fromTop: false))
            .onTapGesture { bottomEdge.isEnabled.toggle() }
    }

    /// Left band: positioned at left edge, inset from top/bottom corners.
    private func leftBandView(
        totalHeight: CGFloat,
        thickness: CGFloat,
        cornerInset: CGFloat
    ) -> some View {
        let isActive = engagedEdge == .left
        let color = bandColorFor(config: leftEdge, isActive: isActive)
        let bandHeight = totalHeight - cornerInset * 2

        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: thickness, height: bandHeight)
            .offset(x: 0, y: cornerInset)
            .gesture(dragGestureHorizontal(config: $leftEdge, parentWidth: thickness, fromLeft: true))
            .onTapGesture { leftEdge.isEnabled.toggle() }
    }

    /// Right band: positioned at right edge, inset from top/bottom corners.
    private func rightBandView(
        totalWidth: CGFloat,
        totalHeight: CGFloat,
        thickness: CGFloat,
        cornerInset: CGFloat
    ) -> some View {
        let isActive = engagedEdge == .right
        let color = bandColorFor(config: rightEdge, isActive: isActive)
        let bandHeight = totalHeight - cornerInset * 2

        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: thickness, height: bandHeight)
            .offset(x: totalWidth - thickness, y: cornerInset)
            .gesture(dragGestureHorizontal(config: $rightEdge, parentWidth: thickness, fromLeft: false))
            .onTapGesture { rightEdge.isEnabled.toggle() }
    }

    // MARK: - Band Thickness Calculation

    /// Calculate the pixel thickness of a band based on its config fraction.
    /// Uses the bandWidth fraction scaled to a reasonable visual range (14-30pt).
    /// Default 0.025 -> ~22pt. Scale proportionally.
    private func bandThickness(for config: EdgeConfig, totalDimension: CGFloat) -> CGFloat {
        let fraction = CGFloat(config.bandWidth)
        let scaled = defaultBandThickness * (fraction / 0.025)
        return max(14, min(30, scaled))
    }

    /// Compute band color based on enabled state and engagement.
    private func bandColorFor(config: EdgeConfig, isActive: Bool) -> Color {
        if !config.isEnabled {
            return Color.gray.opacity(0.15)
        }
        return isActive ? Color.blue.opacity(0.8) : Color.blue.opacity(0.6)
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
