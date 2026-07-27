import CoreAudio
import Foundation
import LedgeCore

/// How much of the full range one step covers, when a backend has to compute an absolute value
/// instead of asking the OS to take a step.
///
/// These are **not** tuning knobs and must not become settings: 16 and 64 are the granularities
/// the OS itself uses for coarse and fine adjustment, so they describe the system being adapted
/// to rather than anything this app decides. `LedgeCore` owns how *often* a step is emitted
/// (`GestureSettings.effectiveStepDistance`); this owns only how big the OS considers a step to
/// be, which `LedgeCore` cannot know and has no opinion about.
///
/// Shared by `CoreAudioVolumeController` and `BrightnessController` so the two backends cannot
/// drift apart and give a slide a different feel depending on which edge it was on.
enum SystemStepFraction {
    static func delta(fine: Bool) -> Float {
        fine ? 1.0 / 64.0 : 1.0 / 16.0
    }
}

/// A way of moving the system volume one step at a time.
///
/// Two implementations exist because they trade off differently, not because either is
/// incomplete — see `VolumeController` and `CoreAudioVolumeController`. Class-bound so the
/// selected backend can be swapped behind a reference without the owner caring which it holds.
protocol VolumeAdjusting: AnyObject {
    func adjust(_ direction: StepDirection, fine: Bool)
    /// The current output volume, 0...1, or nil if it cannot be read. Diagnostics only —
    /// nothing in the gesture path reads this.
    func currentScalar() -> Float?
}

/// The default volume backend: synthesise the media key and let the OS do the work.
///
/// Chosen over CoreAudio for one reason that outweighs everything else — **the OS draws its own
/// HUD when it performs the change itself.** With `OSDUIHelper` gone on Tahoe there is no way to
/// ask for that HUD, so the only way to get it is to not make the change ourselves. Reading the
/// resulting value still goes through CoreAudio, because a posted key tells us nothing about
/// where it landed.
final class VolumeController: VolumeAdjusting {
    func adjust(_ direction: StepDirection, fine: Bool) {
        // A direct translation of the engine's vocabulary into the OS's, not a decision: the
        // engine has already decided a step is due and which way it goes.
        switch direction {
        case .up: MediaKeySender.post(.soundUp, fine: fine)
        case .down: MediaKeySender.post(.soundDown, fine: fine)
        }
    }

    func currentScalar() -> Float? {
        CoreAudioOutput.volumeScalar()
    }
}

/// The alternative volume backend: set the scalar directly through CoreAudio.
///
/// Genuinely continuous — it can move volume by any amount, where a media key can only ask for
/// whatever step the OS feels like taking. It is nonetheless **not** the default, because it
/// produces no HUD at all: the OS has no idea a user asked for anything, so it has nothing to
/// draw. Offered in the menu for anyone who prefers precision to feedback.
final class CoreAudioVolumeController: VolumeAdjusting {
    func adjust(_ direction: StepDirection, fine: Bool) {
        // Raising the volume of a muted device produces a larger silence. Clearing mute on the way
        // up is normalising what "louder" means, not a decision: nobody slides upward in order to
        // stay silent, and the recourse otherwise is the hardware key this app exists to replace.
        // Sliding *down* deliberately leaves mute alone — muting is a state the user chose and a
        // downward step is not a request to leave it.
        //
        // The media-key backend gets this for free: the OS unmutes on volume-up itself, because it
        // is the OS. One more reason it is the default, alongside the HUD.
        if direction == .up {
            CoreAudioOutput.clearMute()
        }

        guard let current = CoreAudioOutput.volumeScalar() else { return }
        let delta = SystemStepFraction.delta(fine: fine)
        let signed = direction == .up ? delta : -delta
        CoreAudioOutput.setVolumeScalar(min(max(current + signed, 0), 1))
    }

    func currentScalar() -> Float? {
        CoreAudioOutput.volumeScalar()
    }
}

/// Thin wrapper over the CoreAudio property calls needed to read and write output volume.
///
/// Deliberately stateless and re-resolves the default output device on every call: the default
/// device changes when headphones are plugged in, and a cached device id would leave the app
/// adjusting something nobody is listening to.
enum CoreAudioOutput {
    /// Elements to try, in order, when looking for a volume property.
    ///
    /// The main element is a device-wide control and is what most built-in outputs expose. Some
    /// devices expose no main volume and only per-channel controls, so channels 1 and 2 (left
    /// and right for stereo) are tried next. This is a capability probe, not a preference.
    ///
    /// UNVERIFIED: that the built-in output exposes a readable `kAudioDevicePropertyVolumeScalar`
    /// on the main element at all. Built-in speakers commonly expose only per-channel controls, in
    /// which case the main-element path never executes and every read and write here lands on
    /// channels 1 and 2 — which for a write means `setVolumeScalar` flattens any deliberate
    /// left/right imbalance, and if a device exposed *neither*, `volumeScalar()` returns nil, the
    /// CoreAudio backend does nothing at all, and the diagnostics window reads the volume as
    /// `unavailable` while the media-key backend keeps working.
    private static let candidateElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain, 1, 2,
    ]

    /// The current output volume, 0...1, or nil if there is no readable volume control.
    ///
    /// Existence is probed by attempting the read and inspecting the status rather than by
    /// calling `AudioObjectHasProperty` first. That is deliberate: a missing property returns
    /// `kAudioHardwareUnknownPropertyError`, which is exactly as informative, and it keeps this
    /// file to CoreAudio calls that return `OSStatus` — an unambiguous `Int32` — instead of ones
    /// returning the C `Boolean` type, whose Swift spelling differs between SDK versions.
    static func volumeScalar() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        for element in candidateElements {
            if let value = read(from: device, element: element) { return value }
        }
        return nil
    }

    /// Set the output volume. `value` is assumed already clamped to 0...1 by the caller.
    static func setVolumeScalar(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }

        // A device-wide control is preferred when present, because writing it keeps the channels
        // balanced however the user had them. Only when there is none do we write channels
        // individually — which does flatten any deliberate imbalance, an accepted cost of a
        // non-default backend on hardware that offers no alternative.
        if write(value, to: device, element: kAudioObjectPropertyElementMain) { return }
        for element in candidateElements where element != kAudioObjectPropertyElementMain {
            _ = write(value, to: device, element: element)
        }
    }

    /// Unmute the default output device, if it has a mute control anywhere.
    ///
    /// Writes 0 rather than reading the current state first: a write of 0 to something already 0
    /// is a no-op, so the read would buy nothing but another way to fail. Existence is probed the
    /// same way as volume — attempt the call, inspect the `OSStatus` — for the same reason: it
    /// keeps this file to CoreAudio calls returning an unambiguous `Int32` and away from ones
    /// returning the C `Boolean` type, whose Swift spelling differs between SDK versions.
    ///
    /// `kAudioDevicePropertyMute` carries a `UInt32`, 1 for muted and 0 for not, which is why this
    /// is written as an integer and not as any kind of boolean.
    static func clearMute() {
        guard let device = defaultOutputDevice() else { return }

        // Main element first, for the same reason as `setVolumeScalar`: a device-wide control is
        // one write instead of two. Falling through to the channels covers devices that expose
        // mute per channel only. Both are attempted rather than assumed, and a device with no
        // mute control at all simply fails every write — which is the correct outcome, since
        // there is then nothing to clear.
        if writeMute(0, to: device, element: kAudioObjectPropertyElementMain) { return }
        for element in candidateElements where element != kAudioObjectPropertyElementMain {
            _ = writeMute(0, to: device, element: element)
        }
    }

    /// - Returns: whether the write succeeded, so the caller can fall through to another element.
    @discardableResult
    private static func writeMute(
        _ value: UInt32,
        to device: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var value = value
        let status = AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
        return status == noErr
    }

    private static func read(from device: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var address = volumeAddress(element: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    /// - Returns: whether the write succeeded, so the caller can fall through to another element.
    @discardableResult
    private static func write(
        _ value: Float,
        to device: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = volumeAddress(element: element)
        var value = Float32(value)
        let status = AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
        return status == noErr
    }

    private static func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        // Compared against a literal rather than `kAudioObjectUnknown` only to keep this file
        // free of constants whose Swift type could surprise us; the value is defined as 0.
        guard status == noErr, device != 0 else { return nil }
        return device
    }
}
