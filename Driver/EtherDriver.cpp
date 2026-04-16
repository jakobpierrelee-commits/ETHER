// ═══════════════════════════════════════════════════════════════════════════════
// Ether — macOS AudioServerPlugIn Driver
//
// Creates a virtual 2ch/48kHz output device. System audio flows in, gets
// processed through an inline EQ, and is forwarded to the real output device.
//
// This file implements the full AudioServerPlugInDriverInterface.
// ═══════════════════════════════════════════════════════════════════════════════

#include "EtherDriver.h"
#include <os/log.h>
#include <string.h>
#include <dispatch/dispatch.h>

static os_log_t sLog = os_log_create("audio.ether.driver", "Driver");

// ─── Forward declarations ────────────────────────────────────────────────────
static EtherDriverState* sDriverState = nullptr;

// COM interface functions
static HRESULT   Ether_QueryInterface(void* driver, REFIID iid, LPVOID* ppv);
static ULONG     Ether_AddRef(void* driver);
static ULONG     Ether_Release(void* driver);
static OSStatus  Ether_Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host);
static OSStatus  Ether_CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef desc, const AudioServerPlugInClientInfo* clientInfo, AudioObjectID* outDeviceID);
static OSStatus  Ether_DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID deviceID);
static OSStatus  Ether_AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, const AudioServerPlugInClientInfo* clientInfo);
static OSStatus  Ether_RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, const AudioServerPlugInClientInfo* clientInfo);
static OSStatus  Ether_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt64 changeAction, void* changeInfo);
static OSStatus  Ether_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt64 changeAction, void* changeInfo);
static Boolean   Ether_HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address);
static OSStatus  Ether_IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, Boolean* outIsSettable);
static OSStatus  Ether_GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32* outDataSize);
static OSStatus  Ether_GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
static OSStatus  Ether_SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, const void* inData);
static OSStatus  Ether_StartIO(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID);
static OSStatus  Ether_StopIO(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID);
static OSStatus  Ether_GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
static OSStatus  Ether_WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, UInt32 operationID, Boolean* outWillDo, Boolean* outWillDoInPlace);
static OSStatus  Ether_BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo* ioCycleInfo);
static OSStatus  Ether_DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, AudioObjectID streamID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo* ioCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
static OSStatus  Ether_EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo* ioCycleInfo);

// ─── VTable ──────────────────────────────────────────────────────────────────
static AudioServerPlugInDriverInterface sDriverInterface = {
    nullptr,  // _reserved
    Ether_QueryInterface,
    Ether_AddRef,
    Ether_Release,
    Ether_Initialize,
    Ether_CreateDevice,
    Ether_DestroyDevice,
    Ether_AddDeviceClient,
    Ether_RemoveDeviceClient,
    Ether_PerformDeviceConfigurationChange,
    Ether_AbortDeviceConfigurationChange,
    Ether_HasProperty,
    Ether_IsPropertySettable,
    Ether_GetPropertyDataSize,
    Ether_GetPropertyData,
    Ether_SetPropertyData,
    Ether_StartIO,
    Ether_StopIO,
    Ether_GetZeroTimeStamp,
    Ether_WillDoIOOperation,
    Ether_BeginIOOperation,
    Ether_DoIOOperation,
    Ether_EndIOOperation
};

static AudioServerPlugInDriverInterface* sDriverInterfacePtr = &sDriverInterface;

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Entry Point
// ═══════════════════════════════════════════════════════════════════════════════

extern "C" void* EtherDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }

    sDriverState = new EtherDriverState();

    // Initialize default EQ (all flat)
    sDriverState->eqParams.bandCount = kEtherMaxBands;
    sDriverState->eqParams.globalGain = 0.0f;
    sDriverState->eqParams.bypass = 0;
    float defaultFreqs[] = {32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
    for (UInt32 i = 0; i < kEtherMaxBands; i++) {
        sDriverState->eqParams.bands[i].frequency = defaultFreqs[i];
        sDriverState->eqParams.bands[i].gain = 0.0f;
        sDriverState->eqParams.bands[i].q = 1.0f;
        sDriverState->eqParams.bands[i].filterType = 0;
        sDriverState->eqParams.bands[i].enabled = 1;
    }

    // Calculate ticks per frame for timing
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    Float64 nanosPerTick = (Float64)timebase.numer / (Float64)timebase.denom;
    Float64 nanosPerFrame = 1e9 / kEtherSampleRate;
    sDriverState->ticksPerFrame = nanosPerFrame / nanosPerTick;

    os_log(sLog, "EtherDriver created — virtual device at %.0f Hz, %u ch", kEtherSampleRate, kEtherNumChannels);

    return &sDriverInterfacePtr;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - COM Interface
// ═══════════════════════════════════════════════════════════════════════════════

static HRESULT Ether_QueryInterface(void* driver, REFIID iid, LPVOID* ppv) {
    CFUUIDRef interfaceID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    bool isPlugin = CFEqual(interfaceID, kAudioServerPlugInDriverInterfaceUUID);
    bool isUnknown = CFEqual(interfaceID, IUnknownUUID);
    CFRelease(interfaceID);

    if (isPlugin || isUnknown) {
        Ether_AddRef(driver);
        *ppv = driver;
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

static ULONG Ether_AddRef(void* driver) {
    return ++(sDriverState->refCount);
}

static ULONG Ether_Release(void* driver) {
    UInt32 count = --(sDriverState->refCount);
    if (count == 0) {
        delete sDriverState;
        sDriverState = nullptr;
    }
    return count;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Initialization
// ═══════════════════════════════════════════════════════════════════════════════

static OSStatus Ether_Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    if (host == nullptr) {
        return kAudioHardwareIllegalOperationError;
    }
    sDriverState->host = host;

    // Notify the host about our device list so it starts querying
    AudioObjectPropertyAddress addr = {
        kAudioPlugInPropertyDeviceList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    host->PropertiesChanged(host, kAudioObjectPlugInObject, 1, &addr);

    os_log(sLog, "Ether initialized");
    return kAudioHardwareNoError;
}

static OSStatus Ether_CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef desc, const AudioServerPlugInClientInfo* clientInfo, AudioObjectID* outDeviceID) {
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus Ether_DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID deviceID) {
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus Ether_AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, const AudioServerPlugInClientInfo* clientInfo) {
    return kAudioHardwareNoError;
}

static OSStatus Ether_RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, const AudioServerPlugInClientInfo* clientInfo) {
    return kAudioHardwareNoError;
}

static OSStatus Ether_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt64 changeAction, void* changeInfo) {
    return kAudioHardwareNoError;
}

static OSStatus Ether_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt64 changeAction, void* changeInfo) {
    return kAudioHardwareNoError;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Property Helpers
// ═══════════════════════════════════════════════════════════════════════════════

#define RETURN_SIZE(type) do { *outDataSize = sizeof(type); return kAudioHardwareNoError; } while(0)

#define RETURN_UINT32(val) do { \
    if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError; \
    *outDataSize = sizeof(UInt32); \
    *(UInt32*)outData = (val); \
    return kAudioHardwareNoError; \
} while(0)

#define RETURN_FLOAT64(val) do { \
    if (inDataSize < sizeof(Float64)) return kAudioHardwareBadPropertySizeError; \
    *outDataSize = sizeof(Float64); \
    *(Float64*)outData = (val); \
    return kAudioHardwareNoError; \
} while(0)

#define RETURN_CFSTRING(str) do { \
    if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError; \
    *outDataSize = sizeof(CFStringRef); \
    *(CFStringRef*)outData = CFSTR(str); \
    return kAudioHardwareNoError; \
} while(0)

#define RETURN_OBJECTID(id) do { \
    if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError; \
    *outDataSize = sizeof(AudioObjectID); \
    *(AudioObjectID*)outData = (id); \
    return kAudioHardwareNoError; \
} while(0)

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Properties
// ═══════════════════════════════════════════════════════════════════════════════

static Boolean Ether_HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address) {
    UInt32 dummySize = 0;
    OSStatus result = Ether_GetPropertyDataSize(driver, objectID, clientPID, address, 0, nullptr, &dummySize);
    return result == kAudioHardwareNoError;
}

static OSStatus Ether_IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, Boolean* outIsSettable) {
    *outIsSettable = false;
    if (address->mSelector == kEtherEQParametersProperty) {
        *outIsSettable = true;
    }
    return kAudioHardwareNoError;
}

static OSStatus Ether_GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32* outDataSize) {
    // ── Plugin ──
    if (objectID == kEtherPlugInObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:       RETURN_SIZE(AudioClassID);
            case kAudioObjectPropertyClass:           RETURN_SIZE(AudioClassID);
            case kAudioObjectPropertyOwner:           RETURN_SIZE(AudioObjectID);
            case kAudioObjectPropertyManufacturer:    RETURN_SIZE(CFStringRef);
            case kAudioObjectPropertyOwnedObjects:    *outDataSize = sizeof(AudioObjectID); return kAudioHardwareNoError;
            case kAudioPlugInPropertyDeviceList:       *outDataSize = sizeof(AudioObjectID); return kAudioHardwareNoError;
            case kAudioPlugInPropertyResourceBundle:   RETURN_SIZE(CFStringRef);
            case kAudioPlugInPropertyBoxList:          *outDataSize = 0; return kAudioHardwareNoError;
            case kAudioPlugInPropertyClockDeviceList:  *outDataSize = 0; return kAudioHardwareNoError;
            case kAudioPlugInPropertyTranslateUIDToDevice:   RETURN_SIZE(AudioObjectID);
            case kAudioPlugInPropertyTranslateUIDToBox:      RETURN_SIZE(AudioObjectID);
            case kAudioPlugInPropertyTranslateUIDToClockDevice: RETURN_SIZE(AudioObjectID);
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0; return kAudioHardwareNoError;
            default: *outDataSize = 0; return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Device ──
    if (objectID == kEtherDeviceObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
            case kAudioObjectPropertyOwner:
            case kAudioDevicePropertyDeviceCanBeDefaultDevice:
            case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            case kAudioDevicePropertyDeviceIsAlive:
            case kAudioDevicePropertyDeviceIsRunning:
            case kAudioDevicePropertyTransportType:
            case kAudioDevicePropertyLatency:
            case kAudioDevicePropertySafetyOffset:
            case kAudioDevicePropertyClockIsStable:
            case kAudioDevicePropertyClockAlgorithm:
                RETURN_SIZE(UInt32);

            case kAudioObjectPropertyControlList:
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyNominalSampleRate:
                RETURN_SIZE(Float64);

            case kAudioDevicePropertyAvailableNominalSampleRates:
                *outDataSize = sizeof(AudioValueRange);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyStreams:
                if (address->mScope == kAudioObjectPropertyScopeInput)
                    *outDataSize = sizeof(AudioObjectID);
                else
                    *outDataSize = sizeof(AudioObjectID);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyOwnedObjects:
                *outDataSize = 2 * sizeof(AudioObjectID);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyName:
            case kAudioObjectPropertyManufacturer:
            case kAudioDevicePropertyDeviceUID:
            case kAudioDevicePropertyModelUID:
            case kAudioDevicePropertyConfigurationApplication:
                RETURN_SIZE(CFStringRef);

            case kAudioDevicePropertyZeroTimeStampPeriod:
                RETURN_SIZE(UInt32);

            case kEtherEQParametersProperty:
                *outDataSize = sizeof(EtherEQParams);
                return kAudioHardwareNoError;

            default:
                *outDataSize = 0;
                return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Streams ──
    if (objectID == kEtherInputStreamObjectID || objectID == kEtherOutputStreamObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
            case kAudioObjectPropertyOwner:
            case kAudioStreamPropertyDirection:
            case kAudioStreamPropertyTerminalType:
            case kAudioStreamPropertyStartingChannel:
            case kAudioStreamPropertyLatency:
                RETURN_SIZE(UInt32);

            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0;
                return kAudioHardwareNoError;

            case kAudioStreamPropertyVirtualFormat:
            case kAudioStreamPropertyPhysicalFormat:
                RETURN_SIZE(AudioStreamBasicDescription);

            case kAudioStreamPropertyAvailableVirtualFormats:
            case kAudioStreamPropertyAvailablePhysicalFormats:
                *outDataSize = sizeof(AudioStreamRangedDescription);
                return kAudioHardwareNoError;

            case kAudioStreamPropertyIsActive:
                RETURN_SIZE(UInt32);

            default:
                *outDataSize = 0;
                return kAudioHardwareUnknownPropertyError;
        }
    }

    *outDataSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus Ether_GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData) {

    // ── Standard format for the device ──
    AudioStreamBasicDescription format = {};
    format.mSampleRate       = kEtherSampleRate;
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mBitsPerChannel   = kEtherBitsPerChannel;
    format.mChannelsPerFrame = kEtherNumChannels;
    format.mBytesPerFrame    = kEtherNumChannels * (kEtherBitsPerChannel / 8);
    format.mFramesPerPacket  = 1;
    format.mBytesPerPacket   = format.mBytesPerFrame;

    // ── Plugin Properties ──
    if (objectID == kEtherPlugInObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:    RETURN_UINT32(kAudioObjectClassID);
            case kAudioObjectPropertyClass:        RETURN_UINT32(kAudioPlugInClassID);
            case kAudioObjectPropertyOwner:        RETURN_OBJECTID(kAudioObjectUnknown);
            case kAudioObjectPropertyManufacturer: RETURN_CFSTRING("Ether Audio");
            case kAudioObjectPropertyOwnedObjects: RETURN_OBJECTID(kEtherDeviceObjectID);
            case kAudioPlugInPropertyDeviceList:    RETURN_OBJECTID(kEtherDeviceObjectID);
            case kAudioPlugInPropertyResourceBundle: RETURN_CFSTRING("");

            case kAudioPlugInPropertyBoxList:
            case kAudioPlugInPropertyClockDeviceList:
                *outDataSize = 0;
                return kAudioHardwareNoError;

            case kAudioPlugInPropertyTranslateUIDToDevice: {
                if (qualifierDataSize == sizeof(CFStringRef) && qualifierData != nullptr) {
                    CFStringRef uid = *(CFStringRef*)qualifierData;
                    if (CFStringCompare(uid, CFSTR("EtherDevice_UID"), 0) == kCFCompareEqualTo) {
                        RETURN_OBJECTID(kEtherDeviceObjectID);
                    }
                }
                RETURN_OBJECTID(kAudioObjectUnknown);
            }

            case kAudioPlugInPropertyTranslateUIDToBox:
            case kAudioPlugInPropertyTranslateUIDToClockDevice:
                RETURN_OBJECTID(kAudioObjectUnknown);

            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Device Properties ──
    if (objectID == kEtherDeviceObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:    RETURN_UINT32(kAudioObjectClassID);
            case kAudioObjectPropertyClass:        RETURN_UINT32(kAudioDeviceClassID);
            case kAudioObjectPropertyOwner:        RETURN_OBJECTID(kEtherPlugInObjectID);
            case kAudioObjectPropertyName:         RETURN_CFSTRING("Ether");
            case kAudioObjectPropertyManufacturer: RETURN_CFSTRING("Ether Audio");
            case kAudioDevicePropertyDeviceUID:    RETURN_CFSTRING("EtherDevice_UID");
            case kAudioDevicePropertyModelUID:     RETURN_CFSTRING("EtherModel_UID");
            case kAudioDevicePropertyConfigurationApplication: RETURN_CFSTRING("audio.ether.app");

            case kAudioDevicePropertyTransportType:     RETURN_UINT32(kAudioDeviceTransportTypeVirtual);
            case kAudioDevicePropertyDeviceCanBeDefaultDevice: RETURN_UINT32(1);
            case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: RETURN_UINT32(1);
            case kAudioDevicePropertyDeviceIsAlive:     RETURN_UINT32(1);
            case kAudioDevicePropertyDeviceIsRunning:    RETURN_UINT32(sDriverState->ioIsRunning ? 1 : 0);
            case kAudioDevicePropertyLatency:           RETURN_UINT32(0);
            case kAudioDevicePropertySafetyOffset:      RETURN_UINT32(0);
            case kAudioDevicePropertyClockIsStable:     RETURN_UINT32(1);
            case kAudioDevicePropertyClockAlgorithm:    RETURN_UINT32(0);

            case kAudioDevicePropertyNominalSampleRate:
                RETURN_FLOAT64(kEtherSampleRate);

            case kAudioDevicePropertyAvailableNominalSampleRates: {
                if (inDataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(AudioValueRange);
                AudioValueRange* range = (AudioValueRange*)outData;
                range->mMinimum = kEtherSampleRate;
                range->mMaximum = kEtherSampleRate;
                return kAudioHardwareNoError;
            }

            case kAudioDevicePropertyZeroTimeStampPeriod:
                RETURN_UINT32(kEtherRingBufferFrames);

            case kAudioDevicePropertyStreams: {
                if (address->mScope == kAudioObjectPropertyScopeInput) {
                    RETURN_OBJECTID(kEtherInputStreamObjectID);
                } else {
                    RETURN_OBJECTID(kEtherOutputStreamObjectID);
                }
            }

            case kAudioObjectPropertyOwnedObjects: {
                if (inDataSize < 2 * sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = 2 * sizeof(AudioObjectID);
                AudioObjectID* ids = (AudioObjectID*)outData;
                ids[0] = kEtherInputStreamObjectID;
                ids[1] = kEtherOutputStreamObjectID;
                return kAudioHardwareNoError;
            }

            case kAudioObjectPropertyControlList:
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0;
                return kAudioHardwareNoError;

            case kEtherEQParametersProperty: {
                if (inDataSize < sizeof(EtherEQParams)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(EtherEQParams);
                pthread_mutex_lock(&sDriverState->eqMutex);
                memcpy(outData, &sDriverState->eqParams, sizeof(EtherEQParams));
                pthread_mutex_unlock(&sDriverState->eqMutex);
                return kAudioHardwareNoError;
            }

            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Stream Properties ──
    if (objectID == kEtherInputStreamObjectID || objectID == kEtherOutputStreamObjectID) {
        bool isInput = (objectID == kEtherInputStreamObjectID);
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:    RETURN_UINT32(kAudioObjectClassID);
            case kAudioObjectPropertyClass:        RETURN_UINT32(kAudioStreamClassID);
            case kAudioObjectPropertyOwner:        RETURN_OBJECTID(kEtherDeviceObjectID);
            case kAudioStreamPropertyIsActive:     RETURN_UINT32(1);
            case kAudioStreamPropertyDirection:     RETURN_UINT32(isInput ? 1 : 0);
            case kAudioStreamPropertyTerminalType:  RETURN_UINT32(isInput ? kAudioStreamTerminalTypeLine : kAudioStreamTerminalTypeSpeaker);
            case kAudioStreamPropertyStartingChannel: RETURN_UINT32(1);
            case kAudioStreamPropertyLatency:      RETURN_UINT32(0);

            case kAudioStreamPropertyVirtualFormat:
            case kAudioStreamPropertyPhysicalFormat: {
                if (inDataSize < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(AudioStreamBasicDescription);
                memcpy(outData, &format, sizeof(AudioStreamBasicDescription));
                return kAudioHardwareNoError;
            }

            case kAudioStreamPropertyAvailableVirtualFormats:
            case kAudioStreamPropertyAvailablePhysicalFormats: {
                if (inDataSize < sizeof(AudioStreamRangedDescription)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(AudioStreamRangedDescription);
                AudioStreamRangedDescription* desc = (AudioStreamRangedDescription*)outData;
                desc->mFormat = format;
                desc->mSampleRateRange.mMinimum = kEtherSampleRate;
                desc->mSampleRateRange.mMaximum = kEtherSampleRate;
                return kAudioHardwareNoError;
            }

            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    return kAudioHardwareUnknownPropertyError;
}

static OSStatus Ether_SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, const void* inData) {

    if (objectID == kEtherDeviceObjectID && address->mSelector == kEtherEQParametersProperty) {
        if (inDataSize < sizeof(EtherEQParams)) return kAudioHardwareBadPropertySizeError;
        pthread_mutex_lock(&sDriverState->eqMutex);
        memcpy(&sDriverState->eqParams, inData, sizeof(EtherEQParams));
        pthread_mutex_unlock(&sDriverState->eqMutex);
        os_log(sLog, "EQ parameters updated from app (bypass=%u, globalGain=%.1f)",
               sDriverState->eqParams.bypass, sDriverState->eqParams.globalGain);
        return kAudioHardwareNoError;
    }

    return kAudioHardwareUnsupportedOperationError;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - I/O Operations
// ═══════════════════════════════════════════════════════════════════════════════

static OSStatus Ether_StartIO(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID) {
    sDriverState->ioClientCount++;
    if (!sDriverState->ioIsRunning) {
        sDriverState->ioIsRunning = true;
        sDriverState->anchorHostTime = mach_absolute_time();
        sDriverState->ioCounter = 0;
        sDriverState->ringWritePos = 0;
        sDriverState->ringReadPos = 0;
        memset(sDriverState->ringBuffer, 0, sizeof(sDriverState->ringBuffer));
        os_log(sLog, "I/O started (client %u)", clientID);
    }
    return kAudioHardwareNoError;
}

static OSStatus Ether_StopIO(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID) {
    if (sDriverState->ioClientCount > 0) {
        sDriverState->ioClientCount--;
    }
    if (sDriverState->ioClientCount == 0) {
        sDriverState->ioIsRunning = false;
        os_log(sLog, "I/O stopped");
    }
    return kAudioHardwareNoError;
}

static OSStatus Ether_GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    UInt64 counter = sDriverState->ioCounter;
    UInt64 periods = counter / kEtherRingBufferFrames;

    *outSampleTime = periods * kEtherRingBufferFrames;
    *outHostTime = sDriverState->anchorHostTime +
                   (UInt64)(periods * kEtherRingBufferFrames * sDriverState->ticksPerFrame);
    *outSeed = 1ULL;

    return kAudioHardwareNoError;
}

static OSStatus Ether_WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, UInt32 operationID, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    *outWillDo = false;
    *outWillDoInPlace = true;

    switch (operationID) {
        case kAudioServerPlugInIOOperationWriteMix:
            *outWillDo = true;   // we receive mixed audio from clients
            break;
        case kAudioServerPlugInIOOperationReadInput:
            *outWillDo = true;   // clients can read our processed output
            break;
    }
    return kAudioHardwareNoError;
}

static OSStatus Ether_BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo* ioCycleInfo) {
    return kAudioHardwareNoError;
}

static OSStatus Ether_DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, AudioObjectID streamID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo* ioCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer) {

    if (operationID == kAudioServerPlugInIOOperationWriteMix) {
        // ── System audio written to our device ───────────────────────────
        // Store in ring buffer for the companion app to read and process.
        float* src = (float*)ioMainBuffer;
        UInt32 framesToWrite = ioBufferFrameSize;
        UInt32 samplesToWrite = framesToWrite * kEtherNumChannels;
        UInt64 writePos = sDriverState->ringWritePos.load(std::memory_order_relaxed);

        for (UInt32 i = 0; i < samplesToWrite; i++) {
            sDriverState->ringBuffer[(writePos + i) % (kEtherRingBufferFrames * kEtherNumChannels)] = src[i];
        }
        sDriverState->ringWritePos.store(writePos + samplesToWrite, std::memory_order_release);
        sDriverState->ioCounter += ioBufferFrameSize;
    }

    if (operationID == kAudioServerPlugInIOOperationReadInput) {
        // ── Companion app reading processed audio back ───────────────────
        // For now, just read from the ring buffer (passthrough).
        // EQ processing will happen here once DSP is implemented.
        float* dst = (float*)ioMainBuffer;
        UInt32 samplesToRead = ioBufferFrameSize * kEtherNumChannels;
        UInt64 readPos = sDriverState->ringReadPos.load(std::memory_order_relaxed);

        for (UInt32 i = 0; i < samplesToRead; i++) {
            dst[i] = sDriverState->ringBuffer[(readPos + i) % (kEtherRingBufferFrames * kEtherNumChannels)];
        }
        sDriverState->ringReadPos.store(readPos + samplesToRead, std::memory_order_release);
    }

    return kAudioHardwareNoError;
}

static OSStatus Ether_EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo* ioCycleInfo) {
    return kAudioHardwareNoError;
}
