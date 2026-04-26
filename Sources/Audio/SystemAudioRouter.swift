import CoreAudio
import AudioToolbox
import os

// MARK: - System Default Output Routing
//
// Wrappers around Core Audio's default output device property.
// Used to route system audio through BlackHole (and restore it afterward).

enum SystemAudioRouter {
    private static let logger = Logger(subsystem: "audio.ether.app", category: "SystemAudioRouter")

    /// Returns the AudioDeviceID of whatever device is currently the system's default output.
    static func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Sets the system's default output device. Returns true on success.
    @discardableResult
    static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        if status != noErr {
            logger.error("Failed to set default output device: OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }

    /// UserDefaults key for persisting the last-known-good output device UID.
    /// Used to recover if the app crashes while routed to BlackHole.
    static let lastGoodOutputKey = "audio.ether.lastGoodOutputUID"

    /// Safety net on launch: if system is currently routed to our Ether driver
    /// (or legacy BlackHole) AND we have a persisted last-good device, restore it.
    /// Handles the case where the app crashed or was force-quit while routed virtual.
    static func restoreOutputIfStuckOnVirtual() {
        guard let currentID = currentDefaultOutputDeviceID() else { return }
        let isEther = AudioDeviceManager.deviceUID(for: currentID) == DriverCommunicator.driverDeviceUID
        let isBlackHole = AudioDeviceManager.deviceName(for: currentID)?.contains("BlackHole") == true
        guard isEther || isBlackHole else { return }

        if let savedUID = UserDefaults.standard.string(forKey: lastGoodOutputKey) {
            for device in AudioDeviceManager.allDevices() where device.uid == savedUID {
                if setDefaultOutputDevice(device.id) {
                    logger.log("Restored system output to \(device.name, privacy: .public) (was stuck on virtual device)")
                    UserDefaults.standard.removeObject(forKey: lastGoodOutputKey)
                }
                return
            }
            logger.warning("Could not find device with UID \(savedUID, privacy: .public) to restore")
        }

        // No saved device — fall back to first physical output (prefer CalDigit)
        let candidates = AudioDeviceManager.outputDevices()
        let fallback = candidates.first(where: { $0.name.contains("CalDigit") }) ?? candidates.first
        if let fallback = fallback, setDefaultOutputDevice(fallback.id) {
            logger.log("Fallback-restored system output to \(fallback.name, privacy: .public) (was stuck on virtual device)")
            UserDefaults.standard.removeObject(forKey: lastGoodOutputKey)
        } else {
            logger.warning("System output is on a virtual device but no physical device found to restore to")
        }
    }
}
