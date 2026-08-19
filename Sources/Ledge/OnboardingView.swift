import AppKit
import Combine
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
// UNVERIFIED: SwiftUI view with @State navigation, Timer.publish, and NSImage bridging on macOS 14+.
struct OnboardingView: View {
    let preferences: Preferences
    let stepCountProvider: () -> Int
    let coordinator: OnboardingCoordinator

    @State private var currentPage = 0
    @State private var isAccessibilityGranted = false
    @State private var stepCount = 0

    /// Timer publishers that SwiftUI manages automatically (cancelled when the view leaves the
    /// hierarchy), fixing the timer leak from the original scheduledTimer approach.
    /// Accessibility poll starts with a 3-second delay so the onboarding window appears BEFORE
    /// any system prompt that AXIsProcessTrustedWithOptions might trigger on first call.
    private let accessibilityTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    private let stepTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    @State private var accessibilityCheckEnabled = false

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
        // UNVERIFIED: .onReceive with Timer.publish for polling AXIsProcessTrusted in SwiftUI.
        .onReceive(accessibilityTimer) { _ in
            guard accessibilityCheckEnabled else { return }
            isAccessibilityGranted = Permissions.isTrusted()
        }
        .onAppear {
            // Delay the first AXIsProcessTrustedWithOptions call by 3 seconds so the onboarding
            // window is fully visible before macOS potentially shows its own system prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                accessibilityCheckEnabled = true
            }
        }
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
        // UNVERIFIED: .onReceive with Timer.publish for polling step count in SwiftUI.
        .onReceive(stepTimer) { _ in
            stepCount = stepCountProvider()
        }
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
                    coordinator.close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Polling (handled via .onReceive modifiers above)
}

/// Coordinator that allows the onboarding view to close its host window without requiring a
/// closure that captures the window reference at view-init time. This avoids the double
/// view-tree construction that occurred when `hostingController.rootView` was replaced after
/// initial assignment.
// UNVERIFIED: @Observable class used as a lightweight coordinator in SwiftUI on macOS 14+.
@Observable
final class OnboardingCoordinator {
    var closeAction: (() -> Void)?

    func close() {
        closeAction?()
    }
}
