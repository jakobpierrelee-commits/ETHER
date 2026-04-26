import CoreAudio
import Foundation
import os

/// Communicates with the Ether AudioServerPlugIn driver via custom AudioObject properties.
/// Finds the "Ether" virtual device and sends EQ parameters to it.
enum DriverCommunicator {

    private static let logger = Logger(subsystem: "audio.ether.app", category: "DriverComm")

    /// Custom property selector for EQ parameters ('EtEQ' = 0x45744551)
    private static let eqPropertySelector = AudioObjectPropertySelector(0x45744551)
    /// Custom property selector for the target physical output device UID ('EtTD').
    /// Driver forwards processed audio to this device internally — eliminates the need
    /// for the app to register an HAL IOProc on the driver's input scope (which would
    /// trigger macOS's orange microphone indicator).
    private static let targetDevicePropertySelector = AudioObjectPropertySelector(0x45745444)
    /// Custom property selector for the forwarding output delay in samples ('EtFL').
    /// Driver pushes its physical output back by this many samples so audio aligns
    /// with the naturally-lagged visualizations.
    private static let forwardingDelayPropertySelector = AudioObjectPropertySelector(0x4574464c)

    /// Stable UID our driver advertises (see Driver/EtherDriver.cpp).
    static let driverDeviceUID = "EtherDevice_UID"

    /// Locate the Ether virtual device by UID — survives device-ID reshuffles
    /// (e.g. coreaudiod restarts) and avoids name collisions.
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
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid) == noErr,
               let uidStr = uid?.takeRetainedValue() as String?,
               uidStr == driverDeviceUID {
                logger.log("Found Ether driver device: id=\(deviceID)")
                return deviceID
            }
        }

        logger.warning("Ether driver not found — run install-driver.sh")
        return nil
    }

    static var isDriverInstalled: Bool {
        findEtherDevice() != nil
    }

    // MARK: - EQ parameter push to driver

    /// Mirror of the C struct `EtherEQParams` in Driver/EtherDriver.h.
    /// Layout MUST match exactly — same field order, same sizes, no padding.
    private struct CEtherEQBand {
        var frequency: Float = 0
        var gain: Float = 0
        var q: Float = 0
        var filterType: UInt32 = 0
        var enabled: UInt32 = 1
    }
    private struct CEtherEQParams {
        var bandCount: UInt32 = 0
        var globalGain: Float = 0
        var bypass: UInt32 = 0
        var bands: (CEtherEQBand, CEtherEQBand, CEtherEQBand, CEtherEQBand, CEtherEQBand,
                    CEtherEQBand, CEtherEQBand, CEtherEQBand, CEtherEQBand, CEtherEQBand) =
            (CEtherEQBand(), CEtherEQBand(), CEtherEQBand(), CEtherEQBand(), CEtherEQBand(),
             CEtherEQBand(), CEtherEQBand(), CEtherEQBand(), CEtherEQBand(), CEtherEQBand())
    }

    /// Push EQ state into the driver. Driver applies biquads in coreaudiod's
    /// process; the Swift app no longer needs to run AVAudioUnitEQ.
    @discardableResult
    static func setEQParams(_ bands: [EQBand], masterGain: Float, bypassed: Bool) -> Bool {
        guard let deviceID = findEtherDevice() else { return false }
        var params = CEtherEQParams()
        params.bandCount  = UInt32(min(bands.count, 10))
        params.globalGain = masterGain
        params.bypass     = bypassed ? 1 : 0

        withUnsafeMutablePointer(to: &params.bands) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CEtherEQBand.self, capacity: 10) { arr in
                for i in 0..<Int(params.bandCount) {
                    let b = bands[i]
                    arr[i].frequency  = b.frequency
                    arr[i].gain       = b.type.usesGain ? b.gain : 0
                    arr[i].q          = b.q
                    arr[i].filterType = UInt32(b.type.rawValue)
                    arr[i].enabled    = b.bypassed ? 0 : 1
                }
            }
        }

        // Wrap the struct in CFData so the HAL routes it through the remote
        // driver IPC as a property-list value. Raw struct bytes don't survive.
        let data = withUnsafeBytes(of: params) { buf -> CFData in
            CFDataCreate(nil, buf.baseAddress?.assumingMemoryBound(to: UInt8.self), buf.count)
        }
        var dataRef: CFData? = data
        var address = AudioObjectPropertyAddress(
            mSelector: eqPropertySelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<CFData?>.size)
        let status = withUnsafePointer(to: &dataRef) { ptr in
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, ptr)
        }
        if status != noErr {
            logger.warning("setEQParams failed: OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }

    /// Tell the driver how many samples to delay its physical output by, so
    /// audio lines up with the naturally-lagged visualizers. The driver caps
    /// this internally; passing 0 disables the delay.
    @discardableResult
    static func setForwardingDelaySamples(_ samples: UInt32) -> Bool {
        guard let deviceID = findEtherDevice() else { return false }
        var copy = samples
        let data = withUnsafeBytes(of: &copy) { buf -> CFData in
            CFDataCreate(nil, buf.baseAddress?.assumingMemoryBound(to: UInt8.self), buf.count)
        }
        var dataRef: CFData? = data
        var address = AudioObjectPropertyAddress(
            mSelector: forwardingDelayPropertySelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<CFData?>.size)
        let status = withUnsafePointer(to: &dataRef) { ptr in
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, ptr)
        }
        if status != noErr {
            logger.warning("setForwardingDelaySamples failed: OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }

    /// Tell the driver to forward processed audio to a specific physical output
    /// (by UID). Pass nil/empty to stop forwarding.
    @discardableResult
    static func setTargetDeviceUID(_ uid: String?) -> Bool {
        guard let deviceID = findEtherDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: targetDevicePropertySelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: CFString? = (uid?.isEmpty == false) ? (uid! as CFString) : ("" as CFString)
        let size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafePointer(to: &cfUID) { ptr in
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, ptr)
        }
        if status != noErr {
            logger.warning("setTargetDeviceUID failed: OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }
}
