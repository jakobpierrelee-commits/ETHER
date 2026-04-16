#pragma once

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <atomic>

// ─── Object IDs ──────────────────────────────────────────────────────────────
enum {
    kEtherPlugInObjectID      = kAudioObjectPlugInObject,  // 1
    kEtherDeviceObjectID      = 2,
    kEtherInputStreamObjectID = 3,   // apps write TO this (system audio in)
    kEtherOutputStreamObjectID = 4,  // we read FROM this (for forwarding)
};

// ─── Device Properties ──────────────────────────────────────────────────────
static const UInt32   kEtherNumChannels    = 2;
static const Float64  kEtherSampleRate     = 48000.0;
static const UInt32   kEtherBitsPerChannel = 32;
static const UInt32   kEtherBufferFrameSize = 512;

// Ring buffer size: enough for ~0.5s at 48kHz stereo
static const UInt32   kEtherRingBufferFrames = 32768;

// Custom property for EQ parameters (app ↔ driver communication)
// 'EtEQ' = 0x45744551
static const AudioObjectPropertySelector kEtherEQParametersProperty = 0x45744551;

// ─── EQ Band ────────────────────────────────────────────────────────────────
struct EtherEQBand {
    Float32 frequency;
    Float32 gain;        // dB
    Float32 q;
    UInt32  filterType;  // 0=parametric, 1=lowShelf, 2=highShelf
    UInt32  enabled;
};

static const UInt32 kEtherMaxBands = 10;

struct EtherEQParams {
    UInt32      bandCount;
    Float32     globalGain;
    UInt32      bypass;
    EtherEQBand bands[kEtherMaxBands];
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

    // Volume / mute
    Float32 volume{1.0f};
    bool    muted{false};
};
