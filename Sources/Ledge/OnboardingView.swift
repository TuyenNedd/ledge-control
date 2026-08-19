import AppKit
import Combine
import SwiftUI

/// A two-page onboarding flow shown on first launch.
///
/// Pages:
/// 1. **Permission** - App icon, welcome text, explains Accessibility requirement, button to
///    open System Settings, live "Waiting for permission..." / "Permission granted" status.
///    Combines the old Welcome and Permission pages into one -- the user sees what the app does
///    and what it needs at the same time.
/// 2. **Try It** - Interactive trackpad preview with live finger tracking, volume/brightness
///    bars, animated arrow hint, and step counter celebration.
///
/// "Continue" on page 1 advances to page 2 (enabled even without permission, but shows a note).
/// "Get Started" on page 2 marks onboarding complete and closes the window.
// UNVERIFIED: SwiftUI view with @State navigation, Timer.publish, and NSImage bridging on macOS 14+.
struct OnboardingView: View {
    let preferences: Preferences
    let stepCountProvider: () -> Int
    let touchPositionProvider: () -> (x: Double, y: Double)?
    let isEngagedProvider: () -> Bool
    let volumeProvider: () -> Float?
    let brightnessProvider: () -> Float?
    let coordinator: OnboardingCoordinator

    @State private var currentPage = 0
    @State private var isAccessibilityGranted = false
    @State private var stepCount = 0
    @State private var accessibilityCheckEnabled = false

    // Live tracking state
    @State private var fingerPosition: CGPoint?
    @State private var isEngaged = false
    @State private var volumeLevel: Float = 0
    @State private var brightnessLevel: Float = 0

    // Animation state
    @State private var arrowOffset: CGFloat = -10
    @State private var arrowVisible = true
    @State private var stepCelebrated = false
    @State private var stepCountScale: CGFloat = 1.0
    @State private var celebrationScale: CGFloat = 1.0
    @State private var getStartedScale: CGFloat = 1.0
    @State private var previousStepCount = 0
    @State private var previousVolume: Float = 0
    @State private var previousBrightness: Float = 0

    /// Timer publishers that SwiftUI manages automatically (cancelled when the view leaves the
    /// hierarchy). Accessibility poll starts only after `accessibilityCheckEnabled` is set.
    private let accessibilityTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    private let stepTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

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
        VStack(spacing: 12) {
            Spacer()

            Text("Try It")
                .font(.title2)
                .fontWeight(.semibold)

            // Trackpad preview with live finger indicator and arrow hint
            ZStack(alignment: .trailing) {
                TrackpadPreviewView(
                    edgeBandWidth: .constant(preferences.gestureSettings.edgeBandWidth),
                    swapSides: preferences.gestureSettings.swapSides,
                    fingerPosition: fingerPosition,
                    isEngaged: isEngaged
                )
                .frame(height: 140)

                // Animated arrow hint (visible only when no steps detected yet)
                // UNVERIFIED: SF Symbol "arrow.up.and.down" with repeating offset animation on macOS 14+.
                if stepCount == 0 && arrowVisible {
                    Image(systemName: "arrow.up.and.down")
                        .font(.title2)
                        .foregroundStyle(.blue.opacity(0.7))
                        .offset(y: arrowOffset)
                        .padding(.trailing, 8)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true)
                            ) {
                                arrowOffset = 10
                            }
                        }
                }
            }
            .padding(.horizontal, 40)

            Text("Slide along the right edge now")
                .font(.body)
                .foregroundStyle(.secondary)

            // Volume/Brightness bars
            controlBars
                .padding(.horizontal, 60)

            // Live step count feedback with celebration
            stepCountView
                .padding(.top, 4)

            if !isAccessibilityGranted {
                Text("Permission not yet granted -- gestures won't work until you allow Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .onReceive(stepTimer) { _ in
            let newStepCount = stepCountProvider()

            // Detect step count changes for animations
            if newStepCount != previousStepCount && newStepCount > 0 {
                // Step count pop animation
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    stepCountScale = 1.2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        stepCountScale = 1.0
                    }
                }

                // Fade out arrow on first step
                if previousStepCount == 0 {
                    withAnimation(.easeOut(duration: 0.3)) {
                        arrowVisible = false
                    }
                }

                // Celebration at 5 steps
                if newStepCount >= 5 && !stepCelebrated {
                    stepCelebrated = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        celebrationScale = 1.1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            celebrationScale = 1.0
                        }
                    }
                    // Pulse the Get Started button
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        getStartedScale = 1.08
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            getStartedScale = 1.0
                        }
                    }
                }

                previousStepCount = newStepCount
            }
            stepCount = newStepCount

            // Update finger position
            if let pos = touchPositionProvider() {
                fingerPosition = CGPoint(x: pos.x, y: pos.y)
            } else {
                fingerPosition = nil
            }

            // Update engaged state
            isEngaged = isEngagedProvider()

            // Update volume/brightness levels
            let newVolume = volumeProvider() ?? 0
            let newBrightness = brightnessProvider() ?? 0

            previousVolume = newVolume
            previousBrightness = newBrightness
            volumeLevel = newVolume
            brightnessLevel = newBrightness
        }
        .onReceive(accessibilityTimer) { _ in
            guard accessibilityCheckEnabled else { return }
            isAccessibilityGranted = Permissions.isTrusted()
        }
    }

    // MARK: - Control Bars (Volume & Brightness)

    // UNVERIFIED: ProgressView linear style on macOS 14+.
    private var controlBars: some View {
        HStack(spacing: 16) {
            // Brightness bar
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                ProgressView(value: Double(brightnessLevel), total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
            }

            // Volume bar
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                ProgressView(value: Double(volumeLevel), total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Step Count View

    private var stepCountView: some View {
        HStack(spacing: 8) {
            if stepCelebrated {
                // Celebration state
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text("It works! You're ready to go.")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "hand.draw")
                    .font(.title3)
                if stepCount == 0 {
                    Text("Waiting for gestures...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Steps detected: \(stepCount)")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
        }
        .scaleEffect(stepCelebrated ? celebrationScale : stepCountScale)
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
                .scaleEffect(getStartedScale)
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
