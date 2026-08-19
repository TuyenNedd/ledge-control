import SwiftUI

/// A visual preview of the trackpad with edge band overlays.
///
/// Shows a rounded rectangle representing the trackpad surface, with semi-transparent blue
/// bands on left and right edges that span the full height and sit flush with (or slightly
/// outside) the trackpad boundary — matching the screenshot reference where the bands wrap
/// around the corners.
///
/// Optionally shows a live finger indicator dot when `fingerPosition` is provided, and
/// a pulse glow animation on the edge bands when `isEngaged` is true.
struct TrackpadPreviewView: View {
    @Binding var edgeBandWidth: Double
    var swapSides: Bool
    /// Optional live finger position mapped to 0...1 normalized space (origin lower-left).
    /// When nil, the finger indicator is hidden.
    var fingerPosition: CGPoint?
    /// Whether the gesture is currently engaged (finger in an edge band and active).
    var isEngaged: Bool

    init(edgeBandWidth: Binding<Double>, swapSides: Bool, fingerPosition: CGPoint? = nil, isEngaged: Bool = false) {
        self._edgeBandWidth = edgeBandWidth
        self.swapSides = swapSides
        self.fingerPosition = fingerPosition
        self.isEngaged = isEngaged
    }

    @State private var edgePulse = false

    private var leftLabel: String {
        swapSides ? "Volume" : "Brightness"
    }

    private var rightLabel: String {
        swapSides ? "Brightness" : "Volume"
    }

    private var mmLabel: String {
        String(format: "%.1f mm", edgeBandWidth * 160.0)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            // Band width proportional to the trackpad, but visually wide enough to see
            let bandPixelWidth = max(CGFloat(edgeBandWidth) * width, 12)

            ZStack {
                // Blue edge bands as background — full height, rounded corners, sitting
                // behind the trackpad surface. This gives the "bands wrapping around" look.
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(isEngaged && edgePulse ? 0.4 : 0.25))

                // Trackpad surface (gray) inset from the bands
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .padding(.leading, bandPixelWidth)
                    .padding(.trailing, bandPixelWidth)

                // Finger indicator dot
                if let pos = fingerPosition {
                    let dotX = pos.x * width
                    let dotY = (1 - pos.y) * height
                    Circle()
                        .fill(isEngaged ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5))
                        .frame(width: 12, height: 12)
                        .position(x: dotX, y: dotY)
                }
            }
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .onChange(of: isEngaged) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
                    edgePulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    edgePulse = false
                }
            } else {
                edgePulse = false
            }
        }
    }
}
