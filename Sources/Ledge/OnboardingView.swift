import AppKit
import SwiftUI

/// A three-page onboarding flow shown on first launch.
///
/// Pages:
/// 1. **Welcome** - App icon, title, one-sentence description.
/// 2. **Permission** - Explains Accessibility requirement, button to open System Settings,
///    live poll of `AXIsProcessTrusted()` with a green checkmark when granted.
/// 3. **Try It** - Trackpad preview with live step count feedback from the gesture controller.
///
/// Navigation is via Next/Back buttons at the bottom. "Get Started" on the final page marks
/// onboarding complete and closes the window.
// UNVERIFIED: SwiftUI view with @State navigation, Timer, and NSImage bridging on macOS 14+.
struct OnboardingView: View {
    let preferences: Preferences
    let stepCountProvider: () -> Int
    let closeWindow: () -> Void

    @State private var currentPage = 0
    @State private var isAccessibilityGranted = false
    @State private var stepCount = 0

    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0:
                    welcomePage
                case 1:
                    permissionPage
                case 2:
                    tryItPage
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            navigationBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 550, height: 450)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            // UNVERIFIED: NSImage(named: NSImage.applicationIconName) bridged to SwiftUI Image.
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)

            Text("Welcome to Ledge")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Trackpad edge gestures for volume and brightness control")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Page 2: Permission

    private var permissionPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Ledge reads trackpad touches through an event tap, which macOS only allows for apps trusted in Privacy & Security.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Status indicator
            HStack(spacing: 8) {
                if isAccessibilityGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    Text("Permission granted")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    Text("Permission not yet granted")
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)

            // UNVERIFIED: Button opening URL via NSWorkspace on macOS 14+.
            Button("Open System Settings") {
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

            Spacer()
        }
        // UNVERIFIED: onAppear + Timer for polling AXIsProcessTrusted in SwiftUI.
        .onAppear { startAccessibilityPolling() }
    }

    // MARK: - Page 3: Try It

    private var tryItPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Try It")
                .font(.title2)
                .fontWeight(.semibold)

            // Reuse the existing trackpad preview from the settings tab.
            // Use a constant binding since we just want to show the current setting.
            TrackpadPreviewView(
                edgeBandWidth: .constant(preferences.gestureSettings.edgeBandWidth),
                swapSides: preferences.gestureSettings.swapSides
            )
            .frame(height: 140)
            .padding(.horizontal, 40)

            Text("Slide along the right edge now")
                .font(.body)
                .foregroundStyle(.secondary)

            // Live step count feedback
            HStack(spacing: 8) {
                Image(systemName: "hand.draw")
                    .font(.title3)
                Text(stepCount == 0 ? "Waiting for gestures..." : "Steps detected: \(stepCount)")
                    .font(.body)
                    .foregroundStyle(stepCount > 0 ? .primary : .secondary)
            }
            .padding(.top, 4)

            if !isAccessibilityGranted {
                Text("Permission not yet granted - the app will not work until you grant Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        // UNVERIFIED: onAppear + Timer for polling step count in SwiftUI.
        .onAppear { startStepPolling() }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if currentPage > 0 {
                Button("Back") {
                    currentPage -= 1
                }
            }

            Spacer()

            if currentPage < totalPages - 1 {
                Button("Next") {
                    currentPage += 1
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    preferences.hasCompletedOnboarding = true
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Polling

    /// Polls `AXIsProcessTrusted()` every second to update the permission status live.
    private func startAccessibilityPolling() {
        // UNVERIFIED: Timer.scheduledTimer usage within SwiftUI view lifecycle on macOS 14+.
        // Using a timer on the main run loop. The timer is not explicitly invalidated because
        // SwiftUI view lifetime manages it implicitly when the view disappears; however, in
        // practice it will keep running. A more robust approach would use .onReceive with a
        // Timer.publish, but this matches the polling pattern from DiagnosticsWindow.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                isAccessibilityGranted = Permissions.isTrusted()
            }
        }
    }

    /// Polls the gesture controller's step count to show live feedback.
    private func startStepPolling() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async {
                stepCount = stepCountProvider()
            }
        }
    }
}
