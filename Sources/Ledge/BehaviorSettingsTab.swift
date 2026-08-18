import SwiftUI

/// The Behavior tab in Settings, containing toggles and sliders for app-level behavior.
struct BehaviorSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        // UNVERIFIED: Form with .grouped style sections on macOS 14+.
        Form {
            Section("General") {
                Toggle("Enabled", isOn: $viewModel.isEnabled)
                Toggle("Freeze Cursor During Gesture", isOn: $viewModel.cursorFreezeEnabled)
                Toggle("Continuous Volume (No HUD)", isOn: $viewModel.useCoreAudioVolume)
                Toggle("Bottom Quarter Only", isOn: $viewModel.bottomQuarterOnly)
            }

            Section("Timing") {
                HStack {
                    Text("Typing Lockout")
                    Spacer()
                    Slider(
                        value: $viewModel.typingLockout,
                        in: 0.2...2.0,
                        step: 0.1,
                        onEditingChanged: viewModel.sliderEditingChanged
                    )
                    .frame(width: 200)
                    Text(String(format: "%.1f s", viewModel.typingLockout))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("Gesture Timeout")
                    Spacer()
                    Slider(
                        value: $viewModel.gestureTimeout,
                        in: 0.1...1.0,
                        step: 0.05,
                        onEditingChanged: viewModel.sliderEditingChanged
                    )
                    .frame(width: 200)
                    Text(String(format: "%.2f s", viewModel.gestureTimeout))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
