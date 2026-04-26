import CoreAudio
import AudioToolbox
import Foundation

// MARK: - AudioDevice Model

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let hasInput: Bool
    let hasOutput: Bool
}

// MARK: - AudioDeviceManager

enum AudioDeviceManager {

    // MARK: - Device Enumeration

    /// Returns all audio devices on the system.
    static func allDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { buildAudioDevice(from: $0) }
    }

    /// Returns all physical output devices (excludes virtual/aggregate devices).
    static func outputDevices() -> [AudioDevice] {
        allDevices().filter { device in
            device.hasOutput
            && !device.name.contains("BlackHole")
            && !device.name.contains("KlipschEQ")
            && device.uid != DriverCommunicator.driverDeviceUID
        }
    }

    /// Finds any output device OTHER than the specified one (for use as aggregate clock source).
    static func anyOtherOutputDevice(excluding deviceID: AudioDeviceID) -> AudioDevice? {
        outputDevices().first(where: { $0.id != deviceID })
    }

    /// Returns the transport type for a device (USB, HDMI, Bluetooth, etc.) as a human string.
    static func transportTypeLabel(for deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &transport)
        guard status == noErr else { return "Unknown" }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:     return "Built-in"
        case kAudioDeviceTransportTypeAggregate:   return "Aggregate"
        case kAudioDeviceTransportTypeVirtual:     return "Virtual"
        case kAudioDeviceTransportTypePCI:         return "PCI"
        case kAudioDeviceTransportTypeUSB:         return "USB"
        case kAudioDeviceTransportTypeFireWire:    return "FireWire"
        case kAudioDeviceTransportTypeBluetooth:   return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
        case kAudioDeviceTransportTypeHDMI:        return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay:     return "AirPlay"
        case kAudioDeviceTransportTypeAVB:         return "AVB"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        default:                                   return "Unknown"
        }
    }

    /// Returns a human-readable format string, e.g. "48 kHz · 32-bit float · 2 ch"
    static func formatDescription(for deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &asbd)
        guard status == noErr else { return "—" }

        let sampleRate = Int(asbd.mSampleRate / 1000)
        let bitDepth = Int(asbd.mBitsPerChannel)
        let channels = Int(asbd.mChannelsPerFrame)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let kind = isFloat ? "float" : "int"
        return "\(sampleRate) kHz · \(bitDepth)-bit \(kind) · \(channels) ch"
    }

    /// Returns our own process's AudioObjectID for tap self-exclusion.
    static func currentProcessAudioObjectID() -> AudioObjectID? {
        let myPID = ProcessInfo.processInfo.processIdentifier

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &processIDs
        ) == noErr else { return nil }

        for processID in processIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(0x70696420), // 'pid '
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(processID, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
               pid == myPID {
                return processID
            }
        }
        return nil
    }

    /// Returns the UID string for a device.
    static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceUID, from: deviceID)
    }

    static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        channelCount(for: deviceID, scope: kAudioObjectPropertyScopeInput)
    }

    static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        channelCount(for: deviceID, scope: kAudioObjectPropertyScopeOutput)
    }

    static func nominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &sampleRate
        )
        guard status == noErr, sampleRate > 0 else { return nil }
        return sampleRate
    }

    /// Returns the human-readable name for a device ID.
    static func deviceName(for deviceID: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceNameCFString, from: deviceID)
    }

    // MARK: - Tap Helpers

    /// Reads the UID of a process tap via kAudioTapPropertyUID.
    static func tapUID(for tapID: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(0x74756964), // 'tuid'
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &size, &uid)
        guard status == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    static func subTapIDs(for aggregateDeviceID: AudioObjectID) -> [AudioObjectID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertySubTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            aggregateDeviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let subTapCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var subTapIDs = [AudioObjectID](repeating: 0, count: subTapCount)
        status = AudioObjectGetPropertyData(
            aggregateDeviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &subTapIDs
        )
        guard status == noErr else { return [] }
        return subTapIDs.filter { $0 != kAudioObjectUnknown }
    }

    // MARK: - Default Devices

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    // MARK: - Private Helpers

    private static func buildAudioDevice(from deviceID: AudioDeviceID) -> AudioDevice? {
        guard let name = stringProperty(kAudioDevicePropertyDeviceNameCFString, from: deviceID) else {
            return nil
        }
        let uid = stringProperty(kAudioDevicePropertyDeviceUID, from: deviceID) ?? ""
        let hasInput = channelCount(for: deviceID, scope: kAudioObjectPropertyScopeInput) > 0
        let hasOutput = channelCount(for: deviceID, scope: kAudioObjectPropertyScopeOutput) > 0

        return AudioDevice(id: deviceID, name: name, uid: uid, hasInput: hasInput, hasOutput: hasOutput)
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector,
                                       from objectID: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func channelCount(for deviceID: AudioDeviceID,
                                     scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
