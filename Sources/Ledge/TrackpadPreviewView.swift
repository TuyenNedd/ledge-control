import SwiftUI

/// A visual preview of the trackpad with edge band overlays.
///
/// Shows a rounded rectangle representing the trackpad surface with a visible border,
/// and semi-transparent blue bands on left and right edges that light up when engaged.
/// No finger-tracking dot — the bands themselves are the feedback.
struct TrackpadPreviewView: View {
    @Binding var edgeBandWidth: Double
    var swapSides: Bool
    /// Which edge is currently engaged: "left", "right", or nil.
    var engagedEdge: String?

    init(edgeBandWidth: Binding<Double>, swapSides: Bool, engagedEdge: String? = nil) {
        self._edgeBandWidth = edgeBandWidth
        self.swapSides = swapSides
        self.engagedEdge = engagedEdge
    }

    // Keep old init for backwards compat (Settings tab uses fingerPosition/isEngaged)
    init(edgeBandWidth: Binding<Double>, swapSides: Bool, fingerPosition: CGPoint?, isEngaged: Bool) {
        self._edgeBandWidth = edgeBandWidth
        self.swapSides = swapSides
        self.engagedEdge = nil
    }

    private var mmLabel: String {
        String(format: "%.1f mm", edgeBandWidth * 160.0)
    }

    private var leftBandActive: Bool {
        engagedEdge == "left"
    }

    private var rightBandActive: Bool {
        engagedEdge == "right"
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bandPixelWidth = max(CGFloat(edgeBandWidth) * width, 14)

            ZStack {
                // Trackpad surface — darker than window background so it's always visible
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1.5)
                    )

                // Left edge band
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(leftBandActive ? Color.blue.opacity(0.6) : Color.blue.opacity(0.2))
                        .frame(width: bandPixelWidth, height: height - 6)
                        .animation(.easeInOut(duration: 0.2), value: leftBandActive)
                    Spacer()
                }
                .padding(.horizontal, 3)

                // Right edge band
                HStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 10)
                        .fill(rightBandActive ? Color.blue.opacity(0.6) : Color.blue.opacity(0.2))
                        .frame(width: bandPixelWidth, height: height - 6)
                        .animation(.easeInOut(duration: 0.2), value: rightBandActive)
                }
                .padding(.horizontal, 3)

                // Center mm label
                Text(mmLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
    }
}
