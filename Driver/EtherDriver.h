#pragma once

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreAudio/CoreAudio.h>          // HAL client side — needed for forwarding IOProc
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <atomic>

// ─── Object IDs ──────────────────────────────────────────────────────────────
// macOS audio hierarchy: PlugIn → Box → Device → Streams + Controls.
// Without a Box, the HAL registrar won't register our device.
enum {
    kEtherPlugInObjectID              = kAudioObjectPlugInObject,  // 1
    kEtherBoxObjectID                 = 2,
    kEtherDeviceObjectID              = 3,
    kEtherInputStreamObjectID         = 4,   // apps write TO this (system audio in)
    kEtherOutputStreamObjectID        = 5,   // we read FROM this (for forwarding)
    kEtherOutputVolumeControlObjectID = 6,
    kEtherOutputMuteControlObjectID   = 7,
};

// dB range matches BlackHole's convention so apps using the slider get
// consistent perceptual stepping.
static const Float32 kEtherVolumeMinDb = -64.0f;
static const Float32 kEtherVolumeMaxDb = 0.0f;

// ─── Device Properties ──────────────────────────────────────────────────────
static const UInt32   kEtherNumChannels    = 2;
static const Float64  kEtherSampleRate     = 48000.0;
static const UInt32   kEtherBitsPerChannel = 32;
static const UInt32   kEtherBufferFrameSize = 512;

// Ring buffer size: enough for ~0.5s at 48kHz stereo
static const UInt32   kEtherRingBufferFrames = 32768;

// Custom properties for app ↔ driver communication.
//   'EtEQ' = EQ parameters (CFData wrapping EtherEQParams)
//   'EtTD' = target physical output device UID (CFString); driver forwards
//           processed audio to this device internally so the app no longer
//           needs to read input streams from us — kills the orange mic dot.
//   'EtFL' = Forwarding output Latency in samples (CFData wrapping UInt32);
//           driver delays its physical output by this many samples so audio
//           lines up with visuals (which naturally lag ~200ms behind).
static const AudioObjectPropertySelector kEtherEQParametersProperty       = 0x45744551;
static const AudioObjectPropertySelector kEtherTargetDeviceUIDProperty    = 0x45745444;
static const AudioObjectPropertySelector kEtherForwardingDelayProperty    = 0x4574464c;

// ─── EQ Band ────────────────────────────────────────────────────────────────
// filterType matches the Swift EQFilterType enum raw values:
//   0 = lowCut (HPF)   1 = lowShelf      2 = bell (parametric)
//   3 = highShelf      4 = highCut (LPF) 5 = notch
struct EtherEQBand {
    Float32 frequency;
    Float32 gain;        // dB
    Float32 q;
    UInt32  filterType;
    UInt32  enabled;
};

static const UInt32 kEtherMaxBands = 10;

struct EtherEQParams {
    UInt32      bandCount;
    Float32     globalGain;
    UInt32      bypass;
    EtherEQBand bands[kEtherMaxBands];
};

// ─── Biquad ────────────────────────────────────────────────────────────────
// One biquad per band. Coefficients are shared across L/R channels; per-channel
// state holds the two-sample delay line. Direct Form I (transposed avoided so
// the audio thread never needs to touch coefs and state in the same iteration).
struct EtherBiquadCoefs {
    Float32 b0, b1, b2, a1, a2;  // a0 is normalized to 1
};
struct EtherBiquadState {
    Float32 z1, z2;              // y[n-1], y[n-2] for transposed Direct Form II
};

// ─── Driver State ───────────────────────────────────────────────────────────
struct EtherDriverState {
    // COM reference count
    std::atomic<UInt32> refCount{1};

    // AudioServerPlugIn host interface
    AudioServerPlugInHostRef host{nullptr};

    // Device state
    std::atomic<bool>   ioIsRunning{false};
    std::atomic<UInt32> ioClientCount{0};

    // Timing
    UInt64  anchorHostTime{0};
    Float64 ticksPerFrame{0};
    std::atomic<UInt64> ioCounter{0};

    // Ring buffer: written by clients (system audio), read by output forwarding
    float   ringBuffer[kEtherRingBufferFrames * kEtherNumChannels]{};
    std::atomic<UInt64> ringWritePos{0};
    std::atomic<UInt64> ringReadPos{0};

    // EQ parameters (set by the Swift app)
    EtherEQParams eqParams{};
    pthread_mutex_t eqMutex = PTHREAD_MUTEX_INITIALIZER;

    // Biquad cascade — one set of coefficients per band, two channels of state.
    // `coefsGen` is bumped every time coefs change so the audio thread can detect
    // and pick them up without locking.
    EtherBiquadCoefs eqCoefs[kEtherMaxBands]{};
    EtherBiquadState eqState[kEtherNumChannels][kEtherMaxBands]{};
    std::atomic<UInt32> coefsGen{0};
    Float32          globalGainLin{1.0f};

    // Volume / mute
    Float32 volume{1.0f};
    bool    muted{false};

    // Phase B: internal forwarding to a physical output device.
    // App writes target UID via kEtherTargetDeviceUIDProperty; driver opens
    // an HAL IOProc on it and pumps the ring buffer to its output stream.
    AudioObjectID         targetDeviceID{kAudioObjectUnknown};
    AudioDeviceIOProcID   targetProcID{nullptr};
    CFStringRef           targetDeviceUID{nullptr};        // retained
    pthread_mutex_t       forwardingMutex = PTHREAD_MUTEX_INITIALIZER;
    // Separate read pointer so the forwarding IOProc doesn't fight with the
    // legacy ReadInput operation (which advances ringReadPos).
    std::atomic<UInt64>   forwardingReadPos{0};
    // Output delay in samples (interleaved): physical output lags behind
    // WriteMix by this many samples so audio lines up with delayed visuals.
    std::atomic<UInt32>   forwardingDelaySamples{0};
};
