import SwiftUI

/// The Gesture tab in Settings, containing the trackpad preview and gesture-related sliders/toggles.
/// Redesigned to match DockDoor-style layout with section headers, full-width sliders, and descriptions.
struct GestureSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Trackpad Preview section
            Text("TRACKPAD PREVIEW")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TrackpadPreviewView(
                edgeBandWidth: $viewModel.edgeBandWidth,
                swapSides: viewModel.swapSides
            )
            .frame(height: 130)

            // MARK: - Edge Sensitivity section
            Text("EDGE SENSITIVITY")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 24)

            // Edge Band Width slider
            Text("Edge Band Width")
                .font(.body)

            HStack(spacing: 8) {
                // UNVERIFIED: Slider with step parameter and onEditingChanged on macOS 14+.
                Slider(
                    value: $viewModel.edgeBandWidth,
                    in: 0.01...0.10,
                    step: 0.005,
                    onEditingChanged: viewModel.sliderEditingChanged
                )
                .frame(maxWidth: .infinity)

                Text(edgeBandWidthLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))
            }

            Text("The zone along the trackpad edge where gestures are detected.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Activation Distance slider
            Text("Activation Distance")
                .font(.body)
                .padding(.top, 12)

            HStack(spacing: 8) {
                Slider(
                    value: $viewModel.activationDistance,
                    in: 0.01...0.10,
                    step: 0.005,
                    onEditingChanged: viewModel.sliderEditingChanged
                )
                .frame(maxWidth: .infinity)

                Text(String(format: "%.3f", viewModel.activationDistance))
                    .font(.caption)
                    .monospacedDigit()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))
            }

            Text("How far you must slide before a gesture activates.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // MARK: - Options section
            Text("OPTIONS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 24)

            Toggle("Fine Control", isOn: $viewModel.fineControl)
            Text("Use smaller volume/brightness steps for precise adjustments.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)

            Toggle("Swap Sides", isOn: $viewModel.swapSides)
                .padding(.top, 8)
            Text("Put volume on the left edge and brightness on the right.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Displays approximate mm value (1.0 fraction = ~160mm trackpad width).
    private var edgeBandWidthLabel: String {
        let mm = viewModel.edgeBandWidth * 160.0
        return String(format: "%.1f mm", mm)
    }
}
