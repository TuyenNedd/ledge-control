import SwiftUI
import LedgeCore

/// The Gesture tab in Settings, containing the interactive trackpad preview and gesture-related sliders/toggles.
///
/// Redesigned for 4-edge support: the old single edgeBandWidth slider and swapSides toggle are
/// replaced by the interactive TrackpadPreviewView where each edge can be independently configured
/// through drag-to-resize, click-to-toggle, and per-edge action pickers.
struct GestureSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Trackpad Preview section
            Text("TRACKPAD PREVIEW")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Click an edge band to enable/disable. Drag to resize. Pick action from dropdowns.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            InteractiveTrackpadPreview(
                leftEdge: $viewModel.leftEdge,
                rightEdge: $viewModel.rightEdge,
                topEdge: $viewModel.topEdge,
                bottomEdge: $viewModel.bottomEdge
            )
            .frame(minHeight: 200, maxHeight: 260)

            // MARK: - Edge Sensitivity section
            Text("EDGE SENSITIVITY")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 24)

            // Activation Distance slider
            Text("Activation Distance")
                .font(.body)

            HStack(spacing: 8) {
                // UNVERIFIED: Slider with step parameter and onEditingChanged on macOS 14+.
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
                .toggleStyle(.switch)
            Text("Use smaller volume/brightness steps for precise adjustments.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
