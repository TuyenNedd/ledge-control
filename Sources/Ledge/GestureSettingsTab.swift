import SwiftUI

/// The Gesture tab in Settings, containing the trackpad preview and gesture-related sliders/toggles.
struct GestureSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        // UNVERIFIED: Form layout with sections inside a TabView tab on macOS 14+.
        Form {
            Section {
                TrackpadPreviewView(
                    edgeBandWidth: $viewModel.edgeBandWidth,
                    swapSides: viewModel.swapSides
                )
                .frame(height: 100)
                .padding(.vertical, 4)
            }

            Section("Edge Width") {
                HStack {
                    // UNVERIFIED: Slider with step parameter and onEditingChanged on macOS.
                    Slider(
                        value: $viewModel.edgeBandWidth,
                        in: 0.01...0.10,
                        step: 0.005,
                        onEditingChanged: viewModel.sliderEditingChanged
                    )
                    Text(edgeBandWidthLabel)
                        .monospacedDigit()
                        .frame(width: 110, alignment: .trailing)
                }
            }

            Section("Activation Distance") {
                HStack {
                    Slider(
                        value: $viewModel.activationDistance,
                        in: 0.01...0.10,
                        step: 0.005,
                        onEditingChanged: viewModel.sliderEditingChanged
                    )
                    Text(String(format: "%.3f", viewModel.activationDistance))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section("Options") {
                Toggle("Fine Control", isOn: $viewModel.fineControl)
                Toggle("Swap Sides", isOn: $viewModel.swapSides)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Displays both the fraction value and approximate mm (1.0 fraction = ~160mm trackpad width).
    private var edgeBandWidthLabel: String {
        let mm = viewModel.edgeBandWidth * 160.0
        return String(format: "%.3f (~%.1f mm)", viewModel.edgeBandWidth, mm)
    }
}
