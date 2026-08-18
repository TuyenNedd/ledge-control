import SwiftUI

/// A visual preview of the trackpad with edge band overlays.
///
/// Shows a 3:2 aspect ratio rounded rectangle representing the trackpad surface, with
/// semi-transparent blue bands on left and right edges whose width updates live from the
/// edge width slider. Labels show which control each side drives.
struct TrackpadPreviewView: View {
    @Binding var edgeBandWidth: Double
    var swapSides: Bool

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
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: bandPixelWidth, height: height - 8)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Right edge band
                HStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.3))
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
            }
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
    }
}
