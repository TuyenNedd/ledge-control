import AppKit
import Combine
import SwiftUI

/// A two-page onboarding flow shown on first launch.
///
/// Pages:
/// 1. **Permission** - App icon, welcome text, explains Accessibility requirement, button to
///    open System Settings, live "Waiting for permission..." / "Permission granted" status.
///    Combines the old Welcome and Permission pages into one — the user sees what the app does
///    and what it needs at the same time.
/// 2. **Try It** - Trackpad preview with live step count feedback from the gesture controller.
///
/// "Continue" on page 1 advances to page 2 (enabled even without permission, but shows a note).
/// "Get Started" on page 2 marks onboarding complete and closes the window.
// UNVERIFIED: SwiftUI view with @State navigation, Timer.publish, and NSImage bridging on macOS 14+.
struct OnboardingView: View {
    let preferences: Preferences
    let stepCountProvider: () -> Int
    let coordinator: OnboardingCoordinator

    @State private var currentPage = 0
    @State private var isAccessibilityGranted = false
    @State private var stepCount = 0
    @State private var accessibilityCheckEnabled = false

    /// Timer publishers that SwiftUI manages automatically (cancelled when the view leaves the
    /// hierarchy). Accessibility poll starts only after `accessibilityCheckEnabled` is set.
    private let accessibilityTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    private let stepTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private let totalPages = 2

    var body: some View {
        VStack(spacing: 0) {
            // Page dots
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)

            // Page content
            Group {
                switch currentPage {
                case 0:
                    permissionPage
                case 1:
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
        .onAppear {
            // Delay the first AXIsProcessTrustedWithOptions call so the window is fully
            // visible before macOS potentially shows its own system prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                accessibilityCheckEnabled = true
            }
        }
    }

    // MARK: - Page 1: Permission (combined Welcome + Permission)

    private var permissionPage: some View {
        VStack(spacing: 16) {
            Spacer()

            // App icon
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)

            Text("Allow Accessibility Access")
                .font(.title)
                .fontWeight(.bold)

            Text("Ledge watches trackpad touches and turns edge slides into volume and brightness changes. macOS calls that kind of superpower \"Accessibility\" and wants your explicit OK.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Open System Settings below, find Ledge in the Accessibility list, and toggle it on.")
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
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permission...")
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)

            // Open Settings button
            Button("Open System Settings") {
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)

            Spacer()
        }
        .onReceive(accessibilityTimer) { _ in
            guard accessibilityCheckEnabled else { return }
            isAccessibilityGranted = Permissions.isTrusted()
        }
    }

    // MARK: - Page 2: Try It

    private var tryItPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Try It")
                .font(.title2)
                .fontWeight(.semibold)

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
                Text("Permission not yet granted — gestures won't work until you allow Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .onReceive(stepTimer) { _ in
            stepCount = stepCountProvider()
        }
        .onReceive(accessibilityTimer) { _ in
            guard accessibilityCheckEnabled else { return }
            isAccessibilityGranted = Permissions.isTrusted()
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
                Button("Continue") {
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
