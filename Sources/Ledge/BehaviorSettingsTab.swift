import SwiftUI
import LedgeCore

/// The Behavior tab in Settings, containing toggles and sliders for app-level behavior.
/// Redesigned to match DockDoor-style layout with section headers, full-width sliders, and descriptions.
struct BehaviorSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Controls section
            Text("CONTROLS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle("Freeze Cursor During Gesture", isOn: $viewModel.cursorFreezeEnabled)
            Text("Keep the mouse pointer still while sliding the edge.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)

            Toggle("Bottom Quarter Only", isOn: $viewModel.bottomQuarterOnly)
                .padding(.top, 8)
            Text("Only detect gestures in the bottom quarter of the trackpad.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)

            Picker("Modifier Key Required", selection: $viewModel.modifierKeyRequired) {
                ForEach(ModifierKeyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .padding(.top, 8)
            Text("Require holding a modifier key before gestures activate.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)

            // MARK: - Timing section
            Text("TIMING")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 24)

            // Typing Lockout slider
            Text("Typing Lockout")
                .font(.body)

            HStack(spacing: 8) {
                // UNVERIFIED: Slider with step parameter and onEditingChanged on macOS 14+.
                Slider(
                    value: $viewModel.typingLockout,
                    in: 0.2...2.0,
                    step: 0.1,
                    onEditingChanged: viewModel.sliderEditingChanged
                )
                .frame(maxWidth: .infinity)

                Text(String(format: "%.1f s", viewModel.typingLockout))
                    .font(.caption)
                    .monospacedDigit()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))
            }

            Text("How long after typing before gestures are re-enabled.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Gesture Timeout slider
            Text("Gesture Timeout")
                .font(.body)
                .padding(.top, 12)

            HStack(spacing: 8) {
                Slider(
                    value: $viewModel.gestureTimeout,
                    in: 0.1...1.0,
                    step: 0.05,
                    onEditingChanged: viewModel.sliderEditingChanged
                )
                .frame(maxWidth: .infinity)

                Text(String(format: "%.2f s", viewModel.gestureTimeout))
                    .font(.caption)
                    .monospacedDigit()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))
            }

            Text("How long a pause before a gesture is considered finished.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
