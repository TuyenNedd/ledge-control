import SwiftUI

/// A visual preview of the trackpad with edge band overlays.
///
/// Shows a 3:2 aspect ratio rounded rectangle representing the trackpad surface, with
/// semi-transparent blue bands on left and right edges whose width updates live from the
/// edge width slider. Labels show which control each side drives.
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

    // UNVERIFIED: default parameter values in SwiftUI struct initializer on macOS 14+.
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
        // UNVERIFIED: GeometryReader with overlays for proportional sizing in SwiftUI on macOS.
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bandPixelWidth = CGFloat(edgeBandWidth) * width

            ZStack {
                // Trackpad background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1)
                    )

                // Left edge band
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(isEngaged && edgePulse ? 0.5 : 0.3))
                        .frame(width: bandPixelWidth, height: height - 8)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Right edge band
                HStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(isEngaged && edgePulse ? 0.5 : 0.3))
                        .frame(width: bandPixelWidth, height: height - 8)
                }
                .padding(.horizontal, 4)

                // Labels
                HStack {
                    VStack {
                        Text(leftLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: max(bandPixelWidth + 20, 60))

                    Spacer()

                    Text(mmLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    VStack {
                        Text(rightLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: max(bandPixelWidth + 20, 60))
                }
                .padding(.horizontal, 8)

                // Finger indicator dot
                // UNVERIFIED: position modifier with computed CGPoint in ZStack on macOS 14+.
                if let pos = fingerPosition {
                    // NormalizedPoint has origin at lower-left (y=0 bottom, y=1 top).
                    // SwiftUI has origin at top-left, so flip Y.
                    let dotX = pos.x * width
                    let dotY = (1 - pos.y) * height
                    Circle()
                        .fill(isEngaged ? Color.blue.opacity(0.8) : Color.gray.opacity(0.6))
                        .frame(width: 12, height: 12)
                        .position(x: dotX, y: dotY)
                }
            }
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        // UNVERIFIED: onChange with isEngaged triggering pulse animation on macOS 14+.
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
