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

    /// Safety net on launch: if system is currently routed to BlackHole AND we
    /// have a persisted last-good device, restore it. Handles the case where the
    /// app crashed or was force-quit while routed to BlackHole.
    static func restoreOutputIfStuckOnBlackHole() {
        guard let currentID = currentDefaultOutputDeviceID(),
              let currentName = AudioDeviceManager.deviceName(for: currentID),
              currentName.contains("BlackHole") else {
            return
        }

        guard let savedUID = UserDefaults.standard.string(forKey: lastGoodOutputKey) else {
            logger.warning("System output is BlackHole but no saved device to restore to")
            return
        }

        for device in AudioDeviceManager.allDevices() where device.uid == savedUID {
            if setDefaultOutputDevice(device.id) {
                logger.log("Restored system output to \(device.name, privacy: .public) (was stuck on BlackHole)")
                UserDefaults.standard.removeObject(forKey: lastGoodOutputKey)
            }
            return
        }

        logger.warning("Could not find device with UID \(savedUID, privacy: .public) to restore")
    }
}
