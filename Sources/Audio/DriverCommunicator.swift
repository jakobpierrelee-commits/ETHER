import CoreAudio
import Foundation
import os

/// Communicates with the Ether AudioServerPlugIn driver via custom AudioObject properties.
/// Finds the "Ether" virtual device and sends EQ parameters to it.
enum DriverCommunicator {

    private static let logger = Logger(subsystem: "audio.ether.app", category: "DriverComm")

    /// The custom property selector for EQ parameters ('EtEQ' = 0x45744551)
    private static let eqPropertySelector = AudioObjectPropertySelector(0x45744551)

    /// Find the BlackHole virtual device (we use BlackHole as the capture source).
    static func findEtherDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        for deviceID in deviceIDs {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name) == noErr,
               let nameStr = name?.takeRetainedValue() as String?,
               nameStr.contains("BlackHole") {
                logger.log("Found BlackHole capture device: id=\(deviceID)")
                return deviceID
            }
        }

        logger.warning("BlackHole not found — install with 'brew install blackhole-2ch'")
        return nil
    }

    static var isDriverInstalled: Bool {
        findEtherDevice() != nil
    }
}
