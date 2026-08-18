import Darwin

/// One tick of the trackpad's haptic engine per emitted step.
///
/// Uses the private `MTActuator` API from `MultitouchSupport.framework` to produce haptic
/// feedback directly on the Mac's Force Touch trackpad. The previous implementation used
/// `NSHapticFeedbackManager.defaultPerformer`, which does NOT produce haptics for LSUIElement
/// (`.accessory` activation policy) apps on macOS 26 Tahoe -- confirmed by on-device testing.
///
/// The MTActuator API is the same mechanism used by other open-source trackpad utilities
/// (e.g. YuriGao/slidr-free) and is the only known working approach for background haptics.
///
/// UNVERIFIED: These are private API signatures resolved via dlsym. They may change between
/// macOS versions without notice. The function signatures, parameter semantics, and device ID
/// conventions are reverse-engineered and not covered by any Apple documentation or stability
/// guarantee.
final class Haptics {
    private let preferences: Preferences

    /// How many haptic pulses have been fired since launch. Diagnostics only.
    private(set) var pulseCount: Int = 0

    /// Whether the MTActuator was successfully opened and is ready to fire.
    private(set) var isAvailable: Bool = false

    // MARK: - Private API function types

    private typealias MTActuatorCreateFromDeviceIDFunc = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias MTActuatorOpenFunc = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias MTActuatorActuateFunc = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float) -> Int32
    private typealias MTActuatorCloseFunc = @convention(c) (UnsafeMutableRawPointer) -> Int32

    // MARK: - Resolved symbols

    private var actuator: UnsafeMutableRawPointer?
    private var actuateFunc: MTActuatorActuateFunc?
    private var closeFunc: MTActuatorCloseFunc?

    init(preferences: Preferences) {
        self.preferences = preferences
        loadActuator()
    }

    deinit {
        if let actuator, let closeFunc {
            _ = closeFunc(actuator)
        }
    }

    /// Pulse once, unless the user has turned haptics off or the actuator is unavailable.
    ///
    /// The preference is read here rather than mirrored into a stored flag, so there is no second
    /// copy to keep in sync with the menu.
    func pulse() {
        guard preferences.hapticsEnabled else { return }
        guard let actuator, let actuateFunc else { return }

        // Actuator ID 1602: a short tick suitable for step feedback.
        // Third param (unknown): 0
        // Fourth param (intensity): 0.0 lets the system decide strength.
        _ = actuateFunc(actuator, 1602, 0, 0.0)
        pulseCount += 1
    }

    // MARK: - Private

    private func loadActuator() {
        // Open MultitouchSupport.framework via dlopen
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY
        ) else {
            return
        }

        // Resolve symbols
        guard let createSym = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let openSym = dlsym(handle, "MTActuatorOpen"),
              let actuateSym = dlsym(handle, "MTActuatorActuate"),
              let closeSym = dlsym(handle, "MTActuatorClose") else {
            return
        }

        let createFunc = unsafeBitCast(createSym, to: MTActuatorCreateFromDeviceIDFunc.self)
        let openFunc = unsafeBitCast(openSym, to: MTActuatorOpenFunc.self)
        actuateFunc = unsafeBitCast(actuateSym, to: MTActuatorActuateFunc.self)
        closeFunc = unsafeBitCast(closeSym, to: MTActuatorCloseFunc.self)

        // Device ID 0 = built-in trackpad on all MacBooks
        guard let ref = createFunc(0) else { return }

        let status = openFunc(ref)
        guard status == 0 else { return }

        actuator = ref
        isAvailable = true
    }
}
