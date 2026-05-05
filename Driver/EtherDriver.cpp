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
#include <math.h>
#include <dispatch/dispatch.h>

static os_log_t sLog = os_log_create("audio.ether.driver", "Driver");

// ─── Forward declarations ────────────────────────────────────────────────────
static EtherDriverState* sDriverState = nullptr;

// Icon URL into the driver bundle's Resources/Ether.icns. Built lazily on first
// kAudioObjectPropertyIcon query so we don't pay the bundle lookup at load.
static CFURLRef sIconURL = nullptr;

static CFURLRef CopyIconURL() {
    if (sIconURL) {
        CFRetain(sIconURL);
        return sIconURL;
    }
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("audio.ether.driver"));
    if (!bundle) return nullptr;
    CFURLRef url = CFBundleCopyResourceURL(bundle, CFSTR("Ether"), CFSTR("icns"), nullptr);
    if (url) {
        sIconURL = (CFURLRef)CFRetain(url);
    }
    return url;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - EQ DSP
// ═══════════════════════════════════════════════════════════════════════════════
// Biquad coefficients per RBJ EQ Cookbook. We store normalized coefs
// (a0=1) and apply them with transposed Direct Form II for one-multiply
// efficiency and good numerical behaviour at high frequencies.

// Filter types match Swift EQFilterType raw values (see EtherDriver.h).
static void ComputeBiquadCoefs(const EtherEQBand& band, Float64 sampleRate, EtherBiquadCoefs& out) {
    if (!band.enabled) {
        out = { 1.0f, 0.0f, 0.0f, 0.0f, 0.0f };  // pass-through
        return;
    }
    const Float64 A     = pow(10.0, band.gain / 40.0);     // sqrt(linear gain)
    const Float64 w0    = 2.0 * M_PI * band.frequency / sampleRate;
    const Float64 cosw0 = cos(w0);
    const Float64 sinw0 = sin(w0);
    const Float64 q     = (band.q > 0.001) ? band.q : 0.7071;
    const Float64 alpha = sinw0 / (2.0 * q);

    Float64 b0, b1, b2, a0, a1, a2;
    switch (band.filterType) {
        case 0: {  // lowCut / HPF
            b0 =  (1 + cosw0) / 2.0;
            b1 = -(1 + cosw0);
            b2 =  (1 + cosw0) / 2.0;
            a0 =   1 + alpha;
            a1 =  -2 * cosw0;
            a2 =   1 - alpha;
            break;
        }
        case 1: {  // low shelf
            const Float64 shelfA = 2.0 * sqrt(A) * alpha;
            b0 =      A * ((A + 1) - (A - 1) * cosw0 + shelfA);
            b1 =  2 * A * ((A - 1) - (A + 1) * cosw0);
            b2 =      A * ((A + 1) - (A - 1) * cosw0 - shelfA);
            a0 =          (A + 1) + (A - 1) * cosw0 + shelfA;
            a1 =     -2 * ((A - 1) + (A + 1) * cosw0);
            a2 =          (A + 1) + (A - 1) * cosw0 - shelfA;
            break;
        }
        case 3: {  // high shelf
            const Float64 shelfA = 2.0 * sqrt(A) * alpha;
            b0 =      A * ((A + 1) + (A - 1) * cosw0 + shelfA);
            b1 = -2 * A * ((A - 1) + (A + 1) * cosw0);
            b2 =      A * ((A + 1) + (A - 1) * cosw0 - shelfA);
            a0 =          (A + 1) - (A - 1) * cosw0 + shelfA;
            a1 =      2 * ((A - 1) - (A + 1) * cosw0);
            a2 =          (A + 1) - (A - 1) * cosw0 - shelfA;
            break;
        }
        case 4: {  // highCut / LPF
            b0 =  (1 - cosw0) / 2.0;
            b1 =   1 - cosw0;
            b2 =  (1 - cosw0) / 2.0;
            a0 =   1 + alpha;
            a1 =  -2 * cosw0;
            a2 =   1 - alpha;
            break;
        }
        case 5: {  // notch
            b0 =   1;
            b1 =  -2 * cosw0;
            b2 =   1;
            a0 =   1 + alpha;
            a1 =  -2 * cosw0;
            a2 =   1 - alpha;
            break;
        }
        default: {  // 2 = bell / peaking parametric
            b0 = 1 + alpha * A;
            b1 = -2 * cosw0;
            b2 = 1 - alpha * A;
            a0 = 1 + alpha / A;
            a1 = -2 * cosw0;
            a2 = 1 - alpha / A;
            break;
        }
    }
    out.b0 = (Float32)(b0 / a0);
    out.b1 = (Float32)(b1 / a0);
    out.b2 = (Float32)(b2 / a0);
    out.a1 = (Float32)(a1 / a0);
    out.a2 = (Float32)(a2 / a0);
}

// Recompute the entire cascade from current eqParams. Caller must hold eqMutex.
static void RecomputeAllCoefs() {
    if (!sDriverState) return;
    for (UInt32 i = 0; i < kEtherMaxBands; i++) {
        ComputeBiquadCoefs(sDriverState->eqParams.bands[i], kEtherSampleRate, sDriverState->eqCoefs[i]);
    }
    sDriverState->globalGainLin = (Float32)pow(10.0, sDriverState->eqParams.globalGain / 20.0);
    sDriverState->coefsGen.fetch_add(1, std::memory_order_release);
}

// Volume scalar ↔ decibel conversions. Linear-in-dB curve so each 0.1 of slider
// movement is roughly the same perceptual loudness step.
static inline Float32 ScalarToDb(Float32 scalar) {
    if (scalar <= 0.00001f) return kEtherVolumeMinDb;
    Float32 db = 20.0f * log10f(scalar);
    if (db < kEtherVolumeMinDb) return kEtherVolumeMinDb;
    if (db > kEtherVolumeMaxDb) return kEtherVolumeMaxDb;
    return db;
}
static inline Float32 DbToScalar(Float32 db) {
    if (db <= kEtherVolumeMinDb) return 0.0f;
    if (db >= kEtherVolumeMaxDb) return 1.0f;
    return powf(10.0f, db / 20.0f);
}

// Smooth limiter: linear up to ±0.95, asymptotes toward ±1.0. Threshold sits
// above typical mastered-music peaks (-0.5 to -1 dB) so program material
// passes untouched; only EQ/gain overshoots above ±0.95 get caught.
static inline float SoftClip(float x) {
    const float t = 0.95f;
    const float ax = fabsf(x);
    if (ax <= t) return x;
    const float sign = (x > 0.0f) ? 1.0f : -1.0f;
    const float over = (ax - t) / (1.0f - t);   // 0 .. ∞
    return sign * (t + (1.0f - t) * over / (1.0f + over));
}

// Apply the cascade to one channel's interleaved samples (stride=numChannels).
// Transposed Direct Form II — only one multiply by b0, two state updates per band.
static inline void ProcessChannel(float* samples, UInt32 frames, UInt32 stride,
                                  UInt32 channelIdx, UInt32 bandCount) {
    for (UInt32 b = 0; b < bandCount; b++) {
        const EtherBiquadCoefs c = sDriverState->eqCoefs[b];
        // Skip pure pass-through bands cheaply
        if (c.b0 == 1.0f && c.b1 == 0.0f && c.b2 == 0.0f && c.a1 == 0.0f && c.a2 == 0.0f) {
            continue;
        }
        EtherBiquadState& s = sDriverState->eqState[channelIdx][b];
        Float32 z1 = s.z1, z2 = s.z2;
        for (UInt32 i = 0; i < frames; i++) {
            const Float32 x = samples[i * stride];
            const Float32 y = c.b0 * x + z1;
            z1 = c.b1 * x - c.a1 * y + z2;
            z2 = c.b2 * x - c.a2 * y;
            samples[i * stride] = y;
        }
        s.z1 = z1;
        s.z2 = z2;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Phase B: Internal Forwarding to Physical Output
// ═══════════════════════════════════════════════════════════════════════════════
// The driver runs inside the Core-Audio-Driver-Service.helper process (a child
// of coreaudiod). That process is allowed to use the public CoreAudio HAL APIs
// to register IOProcs on other devices. By doing so, the Ether app no longer
// needs to read input streams from us — which kills the orange "mic in use"
// indicator at the menu bar.
//
// Flow: app writes EQ'd audio → ring buffer (in WriteMix); our forwarding
// IOProc on the target device pulls from that ring and writes to the device's
// output buffer.

static OSStatus EtherForwardingIOProc(AudioObjectID inDevice,
                                      const AudioTimeStamp* inNow,
                                      const AudioBufferList* inInputData,
                                      const AudioTimeStamp* inInputTime,
                                      AudioBufferList* outOutputData,
                                      const AudioTimeStamp* inOutputTime,
                                      void* inClientData);

// Look up a device by its UID. Returns kAudioObjectUnknown on failure.
static AudioObjectID FindDeviceByUID(CFStringRef uid) {
    if (!uid) return kAudioObjectUnknown;
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(AudioObjectID);
    OSStatus s = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr,
                                            sizeof(CFStringRef), &uid, &size, &deviceID);
    if (s != noErr || deviceID == kAudioObjectUnknown || deviceID == kEtherDeviceObjectID) {
        return kAudioObjectUnknown;
    }
    return deviceID;
}

// Stop and tear down any active forwarding. Must hold forwardingMutex.
static void StopForwardingLocked() {
    if (!sDriverState) return;
    if (sDriverState->targetProcID && sDriverState->targetDeviceID != kAudioObjectUnknown) {
        AudioDeviceStop(sDriverState->targetDeviceID, sDriverState->targetProcID);
        AudioDeviceDestroyIOProcID(sDriverState->targetDeviceID, sDriverState->targetProcID);
        os_log(sLog, "Forwarding stopped (device=%u)", (unsigned)sDriverState->targetDeviceID);
    }
    sDriverState->targetProcID = nullptr;
    sDriverState->targetDeviceID = kAudioObjectUnknown;
    if (sDriverState->targetDeviceUID) {
        CFRelease(sDriverState->targetDeviceUID);
        sDriverState->targetDeviceUID = nullptr;
    }
}

// Start forwarding to the device matching the given UID. Empty/null UID = stop.
// Dispatches the actual HAL calls to a background queue — calling
// AudioDeviceCreateIOProcID/Start synchronously from inside SetPropertyData
// deadlocks because coreaudiod is blocked waiting for THIS Set to return
// before it can service our HAL calls. Async = both sides make progress.
static dispatch_queue_t sForwardingQueue = dispatch_queue_create("audio.ether.driver.forwarding", DISPATCH_QUEUE_SERIAL);

static void StartForwardingAsync(CFStringRef newUID) {
    CFStringRef retainedUID = newUID ? (CFStringRef)CFRetain(newUID) : nullptr;
    dispatch_async(sForwardingQueue, ^{
        pthread_mutex_lock(&sDriverState->forwardingMutex);
        StopForwardingLocked();
        if (!retainedUID || CFStringGetLength(retainedUID) == 0) {
            if (retainedUID) CFRelease(retainedUID);
            pthread_mutex_unlock(&sDriverState->forwardingMutex);
            return;
        }
        AudioObjectID dev = FindDeviceByUID(retainedUID);
        if (dev == kAudioObjectUnknown) {
            os_log(sLog, "Forwarding: no device matches UID");
            CFRelease(retainedUID);
            pthread_mutex_unlock(&sDriverState->forwardingMutex);
            return;
        }
        AudioDeviceIOProcID procID = nullptr;
        OSStatus s = AudioDeviceCreateIOProcID(dev, EtherForwardingIOProc, nullptr, &procID);
        if (s != noErr || !procID) {
            os_log(sLog, "Forwarding: CreateIOProcID failed (status=%d)", s);
            CFRelease(retainedUID);
            pthread_mutex_unlock(&sDriverState->forwardingMutex);
            return;
        }
        s = AudioDeviceStart(dev, procID);
        if (s != noErr) {
            AudioDeviceDestroyIOProcID(dev, procID);
            os_log(sLog, "Forwarding: AudioDeviceStart failed (status=%d)", s);
            CFRelease(retainedUID);
            pthread_mutex_unlock(&sDriverState->forwardingMutex);
            return;
        }
        sDriverState->targetDeviceID  = dev;
        sDriverState->targetProcID    = procID;
        sDriverState->targetDeviceUID = retainedUID;  // ownership transferred
        // Initialize forwarding read pointer behind the write head by:
        //   reservoir (drift slack) + delaySamples (visual-sync compensation).
        const UInt32 reservoirSamples = 1024 * kEtherNumChannels;  // ~21ms @48k
        const UInt32 delaySamples = sDriverState->forwardingDelaySamples.load(std::memory_order_acquire);
        const UInt32 totalLag = reservoirSamples + delaySamples;
        UInt64 wp = sDriverState->ringWritePos.load(std::memory_order_acquire);
        sDriverState->forwardingReadPos.store(
            wp > totalLag ? wp - totalLag : 0,
            std::memory_order_release);
        os_log(sLog, "Forwarding started (device=%u, reservoir=%u frames, delay=%u frames)",
               (unsigned)dev, reservoirSamples / kEtherNumChannels, delaySamples / kEtherNumChannels);
        pthread_mutex_unlock(&sDriverState->forwardingMutex);
    });
}

// IOProc on the target physical device: pull from our ring, write to its output.
// Runs on the target device's audio thread — no allocations, no locks, no logging.
//
// Uses its own forwardingReadPos so it doesn't fight the legacy ReadInput op.
// Underrun guard: if WriteMix hasn't put enough samples in the ring yet,
// output silence rather than reading stale buffer contents.
static OSStatus EtherForwardingIOProc(AudioObjectID inDevice,
                                      const AudioTimeStamp* inNow,
                                      const AudioBufferList* inInputData,
                                      const AudioTimeStamp* inInputTime,
                                      AudioBufferList* outOutputData,
                                      const AudioTimeStamp* inOutputTime,
                                      void* inClientData) {
    if (!sDriverState || !outOutputData || outOutputData->mNumberBuffers == 0) {
        return noErr;
    }
    AudioBuffer& buf = outOutputData->mBuffers[0];
    if (!buf.mData) return noErr;
    const UInt32 outFrames   = buf.mDataByteSize / (buf.mNumberChannels * sizeof(float));
    const UInt32 outChannels = buf.mNumberChannels;
    float* dst = (float*)buf.mData;
    const UInt32 ringSize = kEtherRingBufferFrames * kEtherNumChannels;
    const UInt32 needed   = outFrames * kEtherNumChannels;

    UInt64 writePos = sDriverState->ringWritePos.load(std::memory_order_acquire);
    UInt64 readPos  = sDriverState->forwardingReadPos.load(std::memory_order_relaxed);

    // Underrun: not enough samples queued. Output silence and DO NOT advance
    // readPos — wait for WriteMix to catch up.
    if (writePos < readPos || (writePos - readPos) < needed) {
        memset(dst, 0, buf.mDataByteSize);
        return noErr;
    }

    // Overrun guard: if writer has lapped us, drop forward to recent audio.
    if ((writePos - readPos) > ringSize - needed) {
        readPos = writePos > needed ? writePos - needed : 0;
    }

    for (UInt32 f = 0; f < outFrames; f++) {
        const float l = sDriverState->ringBuffer[(readPos + f * 2 + 0) % ringSize];
        const float r = sDriverState->ringBuffer[(readPos + f * 2 + 1) % ringSize];
        if (outChannels >= 2) {
            dst[f * outChannels + 0] = l;
            dst[f * outChannels + 1] = r;
            for (UInt32 c = 2; c < outChannels; c++) dst[f * outChannels + c] = 0.0f;
        } else {
            dst[f] = (l + r) * 0.5f;
        }
    }
    sDriverState->forwardingReadPos.store(readPos + needed, std::memory_order_release);
    return noErr;
}

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

extern "C" __attribute__((visibility("default"))) void* EtherDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
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
        sDriverState->eqParams.bands[i].filterType = 2;  // bell / parametric (Swift raw)
        sDriverState->eqParams.bands[i].enabled = 1;
    }

    // Calculate ticks per frame for timing
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    Float64 nanosPerTick = (Float64)timebase.numer / (Float64)timebase.denom;
    Float64 nanosPerFrame = 1e9 / kEtherSampleRate;
    sDriverState->ticksPerFrame = nanosPerFrame / nanosPerTick;

    // Compute initial (flat) biquad coefficients
    RecomputeAllCoefs();

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
    os_log(sLog, "Ether initialized — host stored");
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
    os_log(sLog, "HasProperty obj=%u sel=0x%x scope=0x%x",
           (unsigned)objectID, (unsigned)address->mSelector, (unsigned)address->mScope);
    UInt32 dummySize = 0;
    OSStatus result = Ether_GetPropertyDataSize(driver, objectID, clientPID, address, 0, nullptr, &dummySize);
    return result == kAudioHardwareNoError;
}

static OSStatus Ether_IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, Boolean* outIsSettable) {
    *outIsSettable = false;
    if (address->mSelector == kEtherEQParametersProperty ||
        address->mSelector == kEtherTargetDeviceUIDProperty ||
        address->mSelector == kEtherForwardingDelayProperty) {
        *outIsSettable = true;
    }
    if (objectID == kEtherOutputVolumeControlObjectID &&
        (address->mSelector == kAudioLevelControlPropertyScalarValue ||
         address->mSelector == kAudioLevelControlPropertyDecibelValue)) {
        *outIsSettable = true;
    }
    if (objectID == kEtherOutputMuteControlObjectID &&
        address->mSelector == kAudioBooleanControlPropertyValue) {
        *outIsSettable = true;
    }
    return kAudioHardwareNoError;
}

static OSStatus Ether_GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32* outDataSize) {
    os_log(sLog, "GetPropertyDataSize obj=%u sel=0x%x scope=0x%x",
                 (unsigned)objectID, (unsigned)address->mSelector, (unsigned)address->mScope);
    // ── Plugin ──
    if (objectID == kEtherPlugInObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:       RETURN_SIZE(AudioClassID);
            case kAudioObjectPropertyClass:           RETURN_SIZE(AudioClassID);
            case kAudioObjectPropertyOwner:           RETURN_SIZE(AudioObjectID);
            case kAudioObjectPropertyManufacturer:    RETURN_SIZE(CFStringRef);
            // OwnedObjects on the plugin owns the Box (not the Device directly).
            case kAudioObjectPropertyOwnedObjects:    *outDataSize = sizeof(AudioObjectID); return kAudioHardwareNoError;
            case kAudioPlugInPropertyBoxList:         *outDataSize = sizeof(AudioObjectID); return kAudioHardwareNoError;
            case kAudioPlugInPropertyDeviceList:      *outDataSize = sizeof(AudioObjectID); return kAudioHardwareNoError;
            case kAudioPlugInPropertyResourceBundle:  RETURN_SIZE(CFStringRef);
            case kAudioPlugInPropertyClockDeviceList: *outDataSize = 0; return kAudioHardwareNoError;
            case kAudioPlugInPropertyTranslateUIDToDevice:   RETURN_SIZE(AudioObjectID);
            case kAudioPlugInPropertyTranslateUIDToBox:      RETURN_SIZE(AudioObjectID);
            case kAudioPlugInPropertyTranslateUIDToClockDevice: RETURN_SIZE(AudioObjectID);
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0; return kAudioHardwareNoError;
            default: *outDataSize = 0; return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Box ──
    if (objectID == kEtherBoxObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
            case kAudioObjectPropertyOwner:
            case kAudioObjectPropertyIdentify:
            case kAudioBoxPropertyTransportType:
            case kAudioBoxPropertyHasAudio:
            case kAudioBoxPropertyHasVideo:
            case kAudioBoxPropertyHasMIDI:
            case kAudioBoxPropertyIsProtected:
            case kAudioBoxPropertyAcquired:
            case kAudioBoxPropertyAcquisitionFailed:
                RETURN_SIZE(UInt32);
            case kAudioObjectPropertyName:
            case kAudioObjectPropertyModelName:
            case kAudioObjectPropertyManufacturer:
            case kAudioObjectPropertySerialNumber:
            case kAudioObjectPropertyFirmwareVersion:
            case kAudioBoxPropertyBoxUID:
                RETURN_SIZE(CFStringRef);
            case kAudioObjectPropertyOwnedObjects:
            case kAudioBoxPropertyDeviceList:
                *outDataSize = sizeof(AudioObjectID); return kAudioHardwareNoError;
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
            case kAudioObjectPropertyIdentify:
            case kAudioDevicePropertyDeviceCanBeDefaultDevice:
            case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            case kAudioDevicePropertyDeviceIsAlive:
            case kAudioDevicePropertyDeviceIsRunning:
            case kAudioDevicePropertyTransportType:
            case kAudioDevicePropertyLatency:
            case kAudioDevicePropertySafetyOffset:
            case kAudioDevicePropertyClockIsStable:
            case kAudioDevicePropertyClockAlgorithm:
            case kAudioDevicePropertyClockDomain:
            case kAudioDevicePropertyIsHidden:
                RETURN_SIZE(UInt32);

            case kAudioObjectPropertyControlList:
                // 2 controls (volume + mute), output scope only.
                if (address->mScope == kAudioObjectPropertyScopeInput)
                    *outDataSize = 0;
                else
                    *outDataSize = 2 * sizeof(AudioObjectID);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 3 * sizeof(AudioServerPlugInCustomPropertyInfo);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyNominalSampleRate:
                RETURN_SIZE(Float64);

            case kAudioDevicePropertyAvailableNominalSampleRates:
                *outDataSize = sizeof(AudioValueRange);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyPreferredChannelsForStereo:
                *outDataSize = 2 * sizeof(UInt32);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyPreferredChannelLayout:
                *outDataSize = offsetof(AudioChannelLayout, mChannelDescriptions);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyStreams:
                // scope-dependent: 1 stream per scope, 2 for global.
                if (address->mScope == kAudioObjectPropertyScopeGlobal)
                    *outDataSize = 2 * sizeof(AudioObjectID);
                else
                    *outDataSize = sizeof(AudioObjectID);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyRelatedDevices:
                *outDataSize = sizeof(AudioObjectID);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyOwnedObjects:
                // global: 2 streams + 2 controls; output: stream + 2 controls; input: stream
                if (address->mScope == kAudioObjectPropertyScopeGlobal)
                    *outDataSize = 4 * sizeof(AudioObjectID);
                else if (address->mScope == kAudioObjectPropertyScopeOutput)
                    *outDataSize = 3 * sizeof(AudioObjectID);
                else
                    *outDataSize = sizeof(AudioObjectID);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyName:
            case kAudioObjectPropertyModelName:
            case kAudioObjectPropertyManufacturer:
            case kAudioDevicePropertyDeviceUID:
            case kAudioDevicePropertyModelUID:
            case kAudioDevicePropertyConfigurationApplication:
                RETURN_SIZE(CFStringRef);

            case kAudioDevicePropertyIcon:
                RETURN_SIZE(CFURLRef);

            case kAudioDevicePropertyZeroTimeStampPeriod:
                RETURN_SIZE(UInt32);

            case kEtherEQParametersProperty:
                // Property is exposed as CFDataRef wrapping the raw struct.
                *outDataSize = sizeof(CFDataRef);
                return kAudioHardwareNoError;

            case kEtherTargetDeviceUIDProperty:
                *outDataSize = sizeof(CFStringRef);
                return kAudioHardwareNoError;

            case kEtherForwardingDelayProperty:
                *outDataSize = sizeof(CFDataRef);
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

    // ── Volume Control ──
    if (objectID == kEtherOutputVolumeControlObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
            case kAudioObjectPropertyOwner:
            case kAudioControlPropertyScope:
            case kAudioControlPropertyElement:
                RETURN_SIZE(UInt32);
            case kAudioLevelControlPropertyScalarValue:
            case kAudioLevelControlPropertyDecibelValue:
            case kAudioLevelControlPropertyConvertScalarToDecibels:
            case kAudioLevelControlPropertyConvertDecibelsToScalar:
                RETURN_SIZE(Float32);
            case kAudioLevelControlPropertyDecibelRange:
                *outDataSize = sizeof(AudioValueRange); return kAudioHardwareNoError;
            case kAudioObjectPropertyOwnedObjects:
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0; return kAudioHardwareNoError;
            default: *outDataSize = 0; return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Mute Control ──
    if (objectID == kEtherOutputMuteControlObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
            case kAudioObjectPropertyOwner:
            case kAudioControlPropertyScope:
            case kAudioControlPropertyElement:
            case kAudioBooleanControlPropertyValue:
                RETURN_SIZE(UInt32);
            case kAudioObjectPropertyOwnedObjects:
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0; return kAudioHardwareNoError;
            default: *outDataSize = 0; return kAudioHardwareUnknownPropertyError;
        }
    }

    *outDataSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus Ether_GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    os_log(sLog, "GetPropertyData obj=%u sel=0x%x scope=0x%x",
                 (unsigned)objectID, (unsigned)address->mSelector, (unsigned)address->mScope);

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
            case kAudioObjectPropertyOwnedObjects: RETURN_OBJECTID(kEtherBoxObjectID);
            case kAudioPlugInPropertyBoxList:      RETURN_OBJECTID(kEtherBoxObjectID);
            case kAudioPlugInPropertyDeviceList:   RETURN_OBJECTID(kEtherDeviceObjectID);
            case kAudioPlugInPropertyResourceBundle: RETURN_CFSTRING("");

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

            case kAudioPlugInPropertyTranslateUIDToBox: {
                if (qualifierDataSize == sizeof(CFStringRef) && qualifierData != nullptr) {
                    CFStringRef uid = *(CFStringRef*)qualifierData;
                    if (CFStringCompare(uid, CFSTR("EtherBox_UID"), 0) == kCFCompareEqualTo) {
                        RETURN_OBJECTID(kEtherBoxObjectID);
                    }
                }
                RETURN_OBJECTID(kAudioObjectUnknown);
            }

            case kAudioPlugInPropertyTranslateUIDToClockDevice:
                RETURN_OBJECTID(kAudioObjectUnknown);

            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Box Properties ──
    if (objectID == kEtherBoxObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:    RETURN_UINT32(kAudioObjectClassID);
            case kAudioObjectPropertyClass:        RETURN_UINT32(kAudioBoxClassID);
            case kAudioObjectPropertyOwner:        RETURN_OBJECTID(kEtherPlugInObjectID);
            case kAudioObjectPropertyName:         RETURN_CFSTRING("Ether");
            case kAudioObjectPropertyModelName:    RETURN_CFSTRING("Ether Virtual Audio Box");
            case kAudioObjectPropertyManufacturer: RETURN_CFSTRING("Ether Audio");
            case kAudioObjectPropertySerialNumber: RETURN_CFSTRING("");
            case kAudioObjectPropertyFirmwareVersion: RETURN_CFSTRING("");
            case kAudioObjectPropertyIdentify:     RETURN_UINT32(0);

            case kAudioBoxPropertyBoxUID:           RETURN_CFSTRING("EtherBox_UID");
            case kAudioBoxPropertyTransportType:    RETURN_UINT32(kAudioDeviceTransportTypeVirtual);
            case kAudioBoxPropertyHasAudio:         RETURN_UINT32(1);
            case kAudioBoxPropertyHasVideo:         RETURN_UINT32(0);
            case kAudioBoxPropertyHasMIDI:          RETURN_UINT32(0);
            case kAudioBoxPropertyIsProtected:      RETURN_UINT32(0);
            case kAudioBoxPropertyAcquired:         RETURN_UINT32(1);
            case kAudioBoxPropertyAcquisitionFailed: RETURN_UINT32(0);

            case kAudioObjectPropertyOwnedObjects:
            case kAudioBoxPropertyDeviceList:
                RETURN_OBJECTID(kEtherDeviceObjectID);

            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0;
                return kAudioHardwareNoError;

            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Device Properties ──
    if (objectID == kEtherDeviceObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:    RETURN_UINT32(kAudioObjectClassID);
            case kAudioObjectPropertyClass:        RETURN_UINT32(kAudioDeviceClassID);
            case kAudioObjectPropertyOwner:        RETURN_OBJECTID(kEtherBoxObjectID);
            case kAudioObjectPropertyName:         RETURN_CFSTRING("Ether");
            case kAudioObjectPropertyModelName:    RETURN_CFSTRING("Ether Virtual Audio");
            case kAudioObjectPropertyManufacturer: RETURN_CFSTRING("Ether Audio");
            case kAudioObjectPropertyIdentify:     RETURN_UINT32(0);
            case kAudioDevicePropertyDeviceUID:    RETURN_CFSTRING("EtherDevice_UID");
            case kAudioDevicePropertyModelUID:     RETURN_CFSTRING("EtherModel_UID");
            case kAudioDevicePropertyConfigurationApplication: RETURN_CFSTRING("audio.ether.app");
            case kAudioDevicePropertyIsHidden:     RETURN_UINT32(0);
            case kAudioDevicePropertyClockDomain:  RETURN_UINT32(0);

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

            case kAudioDevicePropertyIcon: {
                if (inDataSize < sizeof(CFURLRef)) return kAudioHardwareBadPropertySizeError;
                CFURLRef url = CopyIconURL();
                if (!url) return kAudioHardwareUnknownPropertyError;
                *outDataSize = sizeof(CFURLRef);
                *(CFURLRef*)outData = url;
                return kAudioHardwareNoError;
            }

            case kAudioDevicePropertyZeroTimeStampPeriod:
                RETURN_UINT32(kEtherRingBufferFrames);

            case kAudioDevicePropertyPreferredChannelsForStereo: {
                if (inDataSize < 2 * sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = 2 * sizeof(UInt32);
                UInt32* channels = (UInt32*)outData;
                channels[0] = 1;
                channels[1] = 2;
                return kAudioHardwareNoError;
            }

            case kAudioDevicePropertyPreferredChannelLayout: {
                UInt32 layoutSize = offsetof(AudioChannelLayout, mChannelDescriptions);
                if (inDataSize < layoutSize) return kAudioHardwareBadPropertySizeError;
                *outDataSize = layoutSize;
                AudioChannelLayout* layout = (AudioChannelLayout*)outData;
                layout->mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
                layout->mChannelBitmap = 0;
                layout->mNumberChannelDescriptions = 0;
                return kAudioHardwareNoError;
            }

            case kAudioDevicePropertyRelatedDevices:
                RETURN_OBJECTID(kEtherDeviceObjectID);

            case kAudioDevicePropertyStreams: {
                if (address->mScope == kAudioObjectPropertyScopeInput) {
                    RETURN_OBJECTID(kEtherInputStreamObjectID);
                } else if (address->mScope == kAudioObjectPropertyScopeOutput) {
                    RETURN_OBJECTID(kEtherOutputStreamObjectID);
                } else {
                    // Global: both streams.
                    if (inDataSize < 2 * sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                    *outDataSize = 2 * sizeof(AudioObjectID);
                    AudioObjectID* ids = (AudioObjectID*)outData;
                    ids[0] = kEtherInputStreamObjectID;
                    ids[1] = kEtherOutputStreamObjectID;
                    return kAudioHardwareNoError;
                }
            }

            case kAudioObjectPropertyOwnedObjects: {
                if (address->mScope == kAudioObjectPropertyScopeInput) {
                    RETURN_OBJECTID(kEtherInputStreamObjectID);
                } else if (address->mScope == kAudioObjectPropertyScopeOutput) {
                    if (inDataSize < 3 * sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                    *outDataSize = 3 * sizeof(AudioObjectID);
                    AudioObjectID* ids = (AudioObjectID*)outData;
                    ids[0] = kEtherOutputStreamObjectID;
                    ids[1] = kEtherOutputVolumeControlObjectID;
                    ids[2] = kEtherOutputMuteControlObjectID;
                    return kAudioHardwareNoError;
                } else {
                    if (inDataSize < 4 * sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                    *outDataSize = 4 * sizeof(AudioObjectID);
                    AudioObjectID* ids = (AudioObjectID*)outData;
                    ids[0] = kEtherInputStreamObjectID;
                    ids[1] = kEtherOutputStreamObjectID;
                    ids[2] = kEtherOutputVolumeControlObjectID;
                    ids[3] = kEtherOutputMuteControlObjectID;
                    return kAudioHardwareNoError;
                }
            }

            case kAudioObjectPropertyControlList: {
                // 2 controls (volume + mute), output scope only.
                if (address->mScope == kAudioObjectPropertyScopeInput) {
                    *outDataSize = 0;
                    return kAudioHardwareNoError;
                }
                if (inDataSize < 2 * sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = 2 * sizeof(AudioObjectID);
                AudioObjectID* ids = (AudioObjectID*)outData;
                ids[0] = kEtherOutputVolumeControlObjectID;
                ids[1] = kEtherOutputMuteControlObjectID;
                return kAudioHardwareNoError;
            }

            case kAudioObjectPropertyCustomPropertyInfoList: {
                const UInt32 needed = 3 * sizeof(AudioServerPlugInCustomPropertyInfo);
                if (inDataSize < needed) return kAudioHardwareBadPropertySizeError;
                AudioServerPlugInCustomPropertyInfo* infos =
                    (AudioServerPlugInCustomPropertyInfo*)outData;
                infos[0].mSelector          = kEtherEQParametersProperty;
                infos[0].mPropertyDataType  = kAudioServerPlugInCustomPropertyDataTypeCFPropertyList;
                infos[0].mQualifierDataType = kAudioServerPlugInCustomPropertyDataTypeNone;
                infos[1].mSelector          = kEtherTargetDeviceUIDProperty;
                infos[1].mPropertyDataType  = kAudioServerPlugInCustomPropertyDataTypeCFString;
                infos[1].mQualifierDataType = kAudioServerPlugInCustomPropertyDataTypeNone;
                infos[2].mSelector          = kEtherForwardingDelayProperty;
                infos[2].mPropertyDataType  = kAudioServerPlugInCustomPropertyDataTypeCFPropertyList;
                infos[2].mQualifierDataType = kAudioServerPlugInCustomPropertyDataTypeNone;
                *outDataSize = needed;
                return kAudioHardwareNoError;
            }

            case kEtherEQParametersProperty: {
                if (inDataSize < sizeof(CFDataRef)) return kAudioHardwareBadPropertySizeError;
                pthread_mutex_lock(&sDriverState->eqMutex);
                CFDataRef data = CFDataCreate(nullptr,
                                              (const UInt8*)&sDriverState->eqParams,
                                              sizeof(EtherEQParams));
                pthread_mutex_unlock(&sDriverState->eqMutex);
                if (!data) return kAudioHardwareUnspecifiedError;
                *outDataSize = sizeof(CFDataRef);
                *(CFDataRef*)outData = data;  // caller owns the +1 retain
                return kAudioHardwareNoError;
            }

            case kEtherTargetDeviceUIDProperty: {
                if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
                pthread_mutex_lock(&sDriverState->forwardingMutex);
                CFStringRef uid = sDriverState->targetDeviceUID;
                if (uid) CFRetain(uid);
                pthread_mutex_unlock(&sDriverState->forwardingMutex);
                *outDataSize = sizeof(CFStringRef);
                *(CFStringRef*)outData = uid ? uid : CFSTR("");
                return kAudioHardwareNoError;
            }

            case kEtherForwardingDelayProperty: {
                if (inDataSize < sizeof(CFDataRef)) return kAudioHardwareBadPropertySizeError;
                UInt32 samples = sDriverState->forwardingDelaySamples.load(std::memory_order_relaxed);
                CFDataRef data = CFDataCreate(nullptr, (const UInt8*)&samples, sizeof(samples));
                if (!data) return kAudioHardwareUnspecifiedError;
                *outDataSize = sizeof(CFDataRef);
                *(CFDataRef*)outData = data;
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

    // ── Volume Control Data ──
    if (objectID == kEtherOutputVolumeControlObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:    RETURN_UINT32(kAudioLevelControlClassID);
            case kAudioObjectPropertyClass:        RETURN_UINT32(kAudioVolumeControlClassID);
            case kAudioObjectPropertyOwner:        RETURN_OBJECTID(kEtherDeviceObjectID);
            case kAudioControlPropertyScope:       RETURN_UINT32(kAudioObjectPropertyScopeOutput);
            case kAudioControlPropertyElement:     RETURN_UINT32(kAudioObjectPropertyElementMain);
            case kAudioObjectPropertyOwnedObjects:
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0; return kAudioHardwareNoError;
            case kAudioLevelControlPropertyScalarValue: {
                if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(Float32);
                *(Float32*)outData = sDriverState->volume;
                return kAudioHardwareNoError;
            }
            case kAudioLevelControlPropertyDecibelValue: {
                if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(Float32);
                *(Float32*)outData = ScalarToDb(sDriverState->volume);
                return kAudioHardwareNoError;
            }
            case kAudioLevelControlPropertyDecibelRange: {
                if (inDataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(AudioValueRange);
                AudioValueRange* r = (AudioValueRange*)outData;
                r->mMinimum = kEtherVolumeMinDb;
                r->mMaximum = kEtherVolumeMaxDb;
                return kAudioHardwareNoError;
            }
            case kAudioLevelControlPropertyConvertScalarToDecibels: {
                if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(Float32);
                *(Float32*)outData = ScalarToDb(*(Float32*)outData);
                return kAudioHardwareNoError;
            }
            case kAudioLevelControlPropertyConvertDecibelsToScalar: {
                if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
                *outDataSize = sizeof(Float32);
                *(Float32*)outData = DbToScalar(*(Float32*)outData);
                return kAudioHardwareNoError;
            }
            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    // ── Mute Control Data ──
    if (objectID == kEtherOutputMuteControlObjectID) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:        RETURN_UINT32(kAudioBooleanControlClassID);
            case kAudioObjectPropertyClass:            RETURN_UINT32(kAudioMuteControlClassID);
            case kAudioObjectPropertyOwner:            RETURN_OBJECTID(kEtherDeviceObjectID);
            case kAudioControlPropertyScope:           RETURN_UINT32(kAudioObjectPropertyScopeOutput);
            case kAudioControlPropertyElement:         RETURN_UINT32(kAudioObjectPropertyElementMain);
            case kAudioObjectPropertyOwnedObjects:
            case kAudioObjectPropertyCustomPropertyInfoList:
                *outDataSize = 0; return kAudioHardwareNoError;
            case kAudioBooleanControlPropertyValue:    RETURN_UINT32(sDriverState->muted ? 1 : 0);
            default: return kAudioHardwareUnknownPropertyError;
        }
    }

    return kAudioHardwareUnknownPropertyError;
}

static OSStatus Ether_SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, const void* inData) {

    // ── Volume Control SET (with equality guard — see BlackHole's strategy) ──
    // BlackHole's pattern: if newValue == oldValue, return noErr WITHOUT firing
    // PropertiesChanged. This breaks the cascade where macOS Sound prefs reads
    // the new value, decides to "confirm" it by writing it back, and our
    // unconditional notification triggers another read → infinite loop.
    if (objectID == kEtherOutputVolumeControlObjectID) {
        if (inDataSize < sizeof(Float32) || inData == nullptr) return kAudioHardwareBadPropertySizeError;
        Float32 newScalar;
        if (address->mSelector == kAudioLevelControlPropertyScalarValue) {
            newScalar = *(const Float32*)inData;
            if (newScalar < 0.0f) newScalar = 0.0f; else if (newScalar > 1.0f) newScalar = 1.0f;
        } else if (address->mSelector == kAudioLevelControlPropertyDecibelValue) {
            newScalar = DbToScalar(*(const Float32*)inData);
        } else {
            return kAudioHardwareUnknownPropertyError;
        }
        // EQUALITY GUARD — do nothing if value unchanged (loop-breaker)
        if (sDriverState->volume == newScalar) return kAudioHardwareNoError;
        sDriverState->volume = newScalar;
        // Notify both Scalar and Decibel selectors at scope=Global, element=Main
        // (BlackHole pattern; pre-empts a follow-up read of the other representation)
        if (sDriverState->host) {
            AudioObjectPropertyAddress addrs[2] = {
                { kAudioLevelControlPropertyScalarValue,  kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
                { kAudioLevelControlPropertyDecibelValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
            };
            sDriverState->host->PropertiesChanged(sDriverState->host,
                                                  kEtherOutputVolumeControlObjectID, 2, addrs);
        }
        return kAudioHardwareNoError;
    }

    // ── Mute Control SET (with equality guard) ──
    if (objectID == kEtherOutputMuteControlObjectID &&
        address->mSelector == kAudioBooleanControlPropertyValue) {
        if (inDataSize < sizeof(UInt32) || inData == nullptr) return kAudioHardwareBadPropertySizeError;
        bool newMuted = (*(const UInt32*)inData) != 0;
        if (sDriverState->muted == newMuted) return kAudioHardwareNoError;
        sDriverState->muted = newMuted;
        if (sDriverState->host) {
            AudioObjectPropertyAddress addr = {
                kAudioBooleanControlPropertyValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
            };
            sDriverState->host->PropertiesChanged(sDriverState->host,
                                                  kEtherOutputMuteControlObjectID, 1, &addr);
        }
        return kAudioHardwareNoError;
    }

    if (objectID == kEtherDeviceObjectID && address->mSelector == kEtherEQParametersProperty) {
        if (inDataSize < sizeof(CFDataRef) || inData == nullptr) {
            return kAudioHardwareBadPropertySizeError;
        }
        CFDataRef data = *(CFDataRef*)inData;
        if (data == nullptr || CFGetTypeID(data) != CFDataGetTypeID()) {
            return kAudioHardwareIllegalOperationError;
        }
        if (CFDataGetLength(data) < (CFIndex)sizeof(EtherEQParams)) {
            return kAudioHardwareBadPropertySizeError;
        }
        pthread_mutex_lock(&sDriverState->eqMutex);
        memcpy(&sDriverState->eqParams, CFDataGetBytePtr(data), sizeof(EtherEQParams));
        RecomputeAllCoefs();
        pthread_mutex_unlock(&sDriverState->eqMutex);
        os_log(sLog, "EQ params updated (bypass=%u, gain=%.1fdB, bands=%u)",
               sDriverState->eqParams.bypass,
               sDriverState->eqParams.globalGain,
               sDriverState->eqParams.bandCount);
        return kAudioHardwareNoError;
    }

    if (objectID == kEtherDeviceObjectID && address->mSelector == kEtherTargetDeviceUIDProperty) {
        if (inDataSize < sizeof(CFStringRef) || inData == nullptr) {
            return kAudioHardwareBadPropertySizeError;
        }
        CFStringRef newUID = *(CFStringRef*)inData;
        if (newUID && CFGetTypeID(newUID) != CFStringGetTypeID()) {
            return kAudioHardwareIllegalOperationError;
        }
        // Async: cannot make HAL calls from inside SetPropertyData (deadlock)
        StartForwardingAsync(newUID);
        return kAudioHardwareNoError;
    }

    if (objectID == kEtherDeviceObjectID && address->mSelector == kEtherForwardingDelayProperty) {
        if (inDataSize < sizeof(CFDataRef) || inData == nullptr) {
            return kAudioHardwareBadPropertySizeError;
        }
        CFDataRef data = *(CFDataRef*)inData;
        if (!data || CFGetTypeID(data) != CFDataGetTypeID() ||
            CFDataGetLength(data) < (CFIndex)sizeof(UInt32)) {
            return kAudioHardwareIllegalOperationError;
        }
        UInt32 newSamples = 0;
        memcpy(&newSamples, CFDataGetBytePtr(data), sizeof(UInt32));
        // Cap at half the ring buffer so we always have read headroom.
        const UInt32 maxSamples = (kEtherRingBufferFrames / 2) * kEtherNumChannels;
        if (newSamples > maxSamples) newSamples = maxSamples;
        UInt32 oldSamples = sDriverState->forwardingDelaySamples.exchange(newSamples, std::memory_order_acq_rel);
        if (oldSamples != newSamples) {
            // Re-anchor forwardingReadPos so the new delay takes effect.
            // Brief glitch on change is acceptable — visualSyncSec is set-once.
            const UInt32 reservoirSamples = 1024 * kEtherNumChannels;
            UInt64 wp = sDriverState->ringWritePos.load(std::memory_order_acquire);
            const UInt32 totalLag = newSamples + reservoirSamples;
            sDriverState->forwardingReadPos.store(
                wp > totalLag ? wp - totalLag : 0,
                std::memory_order_release);
            os_log(sLog, "Forwarding delay set to %u samples (~%u ms @48k)",
                   newSamples, (newSamples / kEtherNumChannels) * 1000 / 48000);
        }
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
        // Reset forwarding read pointer too — if StartForwardingAsync ran before
        // this reset, its computed forwardingReadPos would be ahead of the now-zero
        // writePos, causing a permanent underrun. Zeroing it here ensures the
        // forwarding IOProc starts from the beginning of the freshly cleared ring.
        sDriverState->forwardingReadPos = 0;
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
        // volume/mute (pre-EQ — gives EQ headroom when slider is down)
        //   → EQ → master gain → soft-clip → ring buffer.
        // Pure passthrough only when nothing's modifying the signal.
        float* src = (float*)ioMainBuffer;
        const UInt32 framesToWrite  = ioBufferFrameSize;
        const UInt32 samplesToWrite = framesToWrite * kEtherNumChannels;
        const UInt32 bypass         = sDriverState->eqParams.bypass;
        const UInt32 bandCount      = sDriverState->eqParams.bandCount;
        const Float32 g             = sDriverState->globalGainLin;
        const Float32 v             = sDriverState->volume;
        const bool muted            = sDriverState->muted;
        const bool needsProcessing  = muted || v != 1.0f || (!bypass && bandCount > 0) || g != 1.0f;

        if (needsProcessing) {
            if (muted) {
                memset(src, 0, samplesToWrite * sizeof(float));
            } else if (v != 1.0f) {
                for (UInt32 i = 0; i < samplesToWrite; i++) src[i] *= v;
            }
            if (!bypass && bandCount > 0 && !muted) {
                for (UInt32 ch = 0; ch < kEtherNumChannels; ch++) {
                    ProcessChannel(src + ch, framesToWrite, kEtherNumChannels, ch, bandCount);
                }
            }
            if (g != 1.0f || (!bypass && bandCount > 0)) {
                for (UInt32 i = 0; i < samplesToWrite; i++) {
                    src[i] = SoftClip(src[i] * g);
                }
            }
        }

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
