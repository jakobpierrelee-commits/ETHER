import AVFoundation
import CoreAudio
import AudioToolbox
import os

// MARK: - Engine Status

enum EngineStatus: Equatable {
    case stopped
    case starting
    case running
    case error(String)
    case driverNotInstalled

    var label: String {
        switch self {
        case .stopped:              return "Stopped"
        case .starting:             return "Starting…"
        case .running:              return "Running"
        case .error(let m):         return "Error: \(m)"
        case .driverNotInstalled:   return "BlackHole not installed"
        }
    }

    var isRunning: Bool { self == .running }
}

// MARK: - EngineManager

/// Reads from BlackHole (system output → BlackHole) via AVAudioEngine inputNode tap,
/// processes through 10-band EQ, writes to the user's physical speakers.
///
/// Flow:
///   System Audio → BlackHole → Input Engine (installTap) → PlayerNode (Output Engine) → EQ → CalDigit
final class EngineManager: ObservableObject {

    private let logger = Logger(subsystem: "audio.ether.app", category: "EngineManager")

    @Published var status: EngineStatus = .stopped
    @Published var inputDeviceName: String = "—"
    @Published var outputDeviceName: String = "—"
    @Published var selectedOutputDevice: AudioDevice?
    @Published var driverInstalled: Bool = false

    private var outputEngine: AVAudioEngine?
    private var eq: AVAudioUnitEQ?
    private var sourceNode: AVAudioSourceNode?
    private var ringBuffer: FloatRingBuffer?
    private var stereoProcessor: StereoProcessor?
    private var reverbNode: AVAudioUnitReverb?
    private var syncDelayNode: AVAudioUnitDelay?

    /// Spatial / stereo processing state — exposed for the UI to write.
    let spatial = SpatialController()

    /// Simple dehisser (downward expander on highs + static shelf trim).
    let denoise = DenoiseController()

    /// ITU-R BS.1770 loudness meter, fed from the post-EQ signal.
    let loudness = LoudnessMeter()

    // Raw HAL I/O proc on BlackHole — bypasses AVFoundation's microphone permission
    // so no orange "in use" indicator appears in the menu bar.
    private var blackHoleDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var blackHoleProcID: AudioDeviceIOProcID?

    // Side-channel ring buffer for the spectrum analyzer.
    // The HAL I/O proc writes here atomically; a main-thread timer reads + feeds the analyzer.
    private var analyzerRingBuffer: FloatRingBuffer?
    private var analyzerTimer: Timer?

    /// Weak reference to the EQ controller so we can re-apply the saved profile
    /// onto the freshly-created AVAudioUnitEQ node whenever the engine starts.
    weak var controller: EQController?

    /// Pre-EQ spectrum (raw system audio from BlackHole).
    let spectrum = SpectrumAnalyzer()

    /// Post-EQ spectrum (what's actually being sent to the speakers).
    let postSpectrum = SpectrumAnalyzer()

    /// Rolling-average analyzer for the "AI Suggest" tonal correction feature.
    let autoEQ = AutoEQAnalyzer()

    /// Continuous adaptive EQ engine (Gullfoss-style). Writes a small offset per band.
    let adaptive = AdaptiveEQ()

    /// Reference-track matcher — loads a file, analyzes its spectrum, proposes band gains.
    let referenceMatcher = ReferenceMatcher()

    /// Post-EQ analyzer ring buffer — fed from an installTap on the EQ node.
    private var postAnalyzerRingBuffer: FloatRingBuffer?

    /// Visual sync offset in seconds (0–0.5). Persisted across launches.
    /// Delays the audio output (via AVAudioUnitDelay after the EQ tap) so visuals appear earlier.
    @Published var visualSyncSec: Float = 0 {
        didSet {
            UserDefaults.standard.set(visualSyncSec, forKey: "audio.ether.visualOffset")
            syncDelayNode?.delayTime = TimeInterval(visualSyncSec)
        }
    }

    /// The system default output device at the time Start was clicked.
    /// Restored when the engine stops.
    private var previousDefaultOutputDeviceID: AudioDeviceID?

    private var defaultFrequencies: [Float] { EQController.defaultFrequencies }

    init() {
        driverInstalled = DriverCommunicator.isDriverInstalled
        // Feed every spectrum frame into the AutoEQ rolling average
        spectrum.onFrame = { [weak self] frame in
            self?.autoEQ.absorbFrame(frame)
        }
        // Adaptive EQ shares the autoEQ's rolling average
        adaptive.autoEQ = autoEQ
        // When adaptive offsets change, re-apply the EQ so user_gain + offset lands on the bands
        adaptive.onChange = { [weak self] in
            guard let self = self, let ctrl = self.controller else { return }
            MainActor.assumeIsolated {
                self.applyEQ(bands: ctrl.bands, masterGain: ctrl.masterGain, bypassed: ctrl.bypassed)
            }
        }
    }

    deinit {
        // stop() touches @MainActor state; teardown + restore directly is safe
        if let prev = previousDefaultOutputDeviceID {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var id = prev
            AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                UInt32(MemoryLayout<AudioDeviceID>.size), &id
            )
        }
        outputEngine?.stop()
        if let procID = blackHoleProcID, blackHoleDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(blackHoleDeviceID, procID)
        }
    }

    func start() {
        guard let outputDevice = selectedOutputDevice else {
            status = .error("No output device selected")
            return
        }
        guard let blackHoleID = DriverCommunicator.findEtherDevice() else {
            status = .driverNotInstalled
            return
        }
        status = .starting

        // Remember current system default output so we can restore it on stop
        previousDefaultOutputDeviceID = SystemAudioRouter.currentDefaultOutputDeviceID()

        // Persist the device UID so we can recover across crashes
        if let prevID = previousDefaultOutputDeviceID,
           prevID != blackHoleID,
           let prevUID = AudioDeviceManager.deviceUID(for: prevID) {
            UserDefaults.standard.set(prevUID, forKey: SystemAudioRouter.lastGoodOutputKey)
        }

        // Route system audio to BlackHole so it flows through our EQ
        if !SystemAudioRouter.setDefaultOutputDevice(blackHoleID) {
            logger.warning("Could not switch system output to BlackHole — user may need to do it manually")
        }

        do {
            try buildAndStart(blackHoleID: blackHoleID, outputDevice: outputDevice)

            // Push the controller's saved profile state onto the fresh EQ node
            // so the user doesn't have to nudge a control to wake it up.
            // start() is called from the main actor so these reads are safe.
            if let ctrl = controller {
                MainActor.assumeIsolated {
                    applyEQ(bands: ctrl.bands, masterGain: ctrl.masterGain, bypassed: ctrl.bypassed)
                }
            }

            // Start at 0 volume, fade up over 50ms to eliminate startup click
            outputEngine?.mainMixerNode.outputVolume = 0
            fadeVolume(to: 1, duration: 0.05) {}
            outputDeviceName = outputDevice.name
            inputDeviceName = "BlackHole 2ch"
            status = .running
        } catch {
            logger.error("Start failed: \(error.localizedDescription, privacy: .public)")
            // Restore system output on failure
            if let previous = previousDefaultOutputDeviceID {
                _ = SystemAudioRouter.setDefaultOutputDevice(previous)
            }
            status = .error(error.localizedDescription)
        }
    }

    func stop() {
        // Soft fade-out to avoid click on teardown
        fadeVolume(to: 0, duration: 0.05) { [weak self] in
            guard let self = self else { return }
            self.teardown()

            if let previous = self.previousDefaultOutputDeviceID {
                _ = SystemAudioRouter.setDefaultOutputDevice(previous)
                self.previousDefaultOutputDeviceID = nil
                UserDefaults.standard.removeObject(forKey: SystemAudioRouter.lastGoodOutputKey)
            }

            self.inputDeviceName = "—"
            self.outputDeviceName = "—"
            self.status = .stopped
        }
    }

    /// Ramp the output mixer's volume over `duration` seconds, then call `completion`.
    private func fadeVolume(to target: Float, duration: TimeInterval, completion: @escaping () -> Void) {
        guard let mixer = outputEngine?.mainMixerNode else { completion(); return }
        let start = mixer.outputVolume
        let steps = 20
        let stepDur = duration / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDur * Double(i)) {
                let t = Float(i) / Float(steps)
                mixer.outputVolume = start + (target - start) * t
                if i == steps { completion() }
            }
        }
    }

    /// Called from AppDelegate on app termination.
    /// Synchronously tears down audio and restores the user's output device.
    func emergencyRestore() {
        teardown()
        if let previous = previousDefaultOutputDeviceID {
            _ = SystemAudioRouter.setDefaultOutputDevice(previous)
            previousDefaultOutputDeviceID = nil
            UserDefaults.standard.removeObject(forKey: SystemAudioRouter.lastGoodOutputKey)
        }
    }

    /// Safety net on launch: if system is currently routed to BlackHole AND we
    /// have a persisted last-good device, restore it. Handles crash/force-quit
    /// while routed to BlackHole. Delegates to SystemAudioRouter.
    func restoreOutputIfStuckOnBlackHole() {
        SystemAudioRouter.restoreOutputIfStuckOnBlackHole()
    }

    // MARK: - Build / Teardown

    private func buildAndStart(blackHoleID: AudioDeviceID, outputDevice: AudioDevice) throws {
        teardown()

        // AVAudioEngine uses deinterleaved standard format internally
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        // ── Ring buffer: producer = input tap, consumer = output source node ──
        // 0.5 sec capacity is way more than needed; read/write positions stay close.
        let ring = FloatRingBuffer(capacityFrames: 24000, channelCount: 2)
        self.ringBuffer = ring

        // ── Output engine: sourceNode → EQ → CalDigit ──
        let outEngine = AVAudioEngine()
        guard let outputAU = outEngine.outputNode.audioUnit else { throw EngineError.noAudioUnit("output") }
        try setDevice(outputDevice.id, on: outputAU, label: "output")

        // Pre-allocate the stereo processor so we can apply width/bass-mono/crossfeed
        // inline on the audio thread without allocations.
        let processor = StereoProcessor(sampleRate: Float(format.sampleRate))
        self.stereoProcessor = processor
        spatial.processor = processor
        denoise.processor = processor

        // Restore saved visual sync setting
        self.visualSyncSec = UserDefaults.standard.float(forKey: "audio.ether.visualOffset")

        // Source node pulls from the ring buffer in its render callback — no queuing.
        // Ring stores interleaved; outputs deinterleaved (one buffer per channel),
        // applies stereo DSP in-place before handing off to the EQ.
        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let bufferListPtr = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let numChannels = bufferListPtr.count
            let frames = Int(frameCount)

            // Pull interleaved from ring, deinterleave into the output buffers
            var interleaved = [Float](repeating: 0, count: frames * numChannels)
            interleaved.withUnsafeMutableBufferPointer { ptr in
                _ = ring.read(dst: ptr.baseAddress!, count: frames)
            }

            for ch in 0..<numChannels {
                if let dst = bufferListPtr[ch].mData?.assumingMemoryBound(to: Float.self) {
                    for f in 0..<frames {
                        dst[f] = interleaved[f * numChannels + ch]
                    }
                }
            }

            // Apply stereo DSP in-place (width, bass-mono, crossfeed)
            if numChannels >= 2,
               let lPtr = bufferListPtr[0].mData?.assumingMemoryBound(to: Float.self),
               let rPtr = bufferListPtr[1].mData?.assumingMemoryBound(to: Float.self) {
                processor.process(l: lPtr, r: rPtr, frameCount: frames)
            }

            return noErr
        }
        outEngine.attach(sourceNode)

        let eq = AVAudioUnitEQ(numberOfBands: 10)
        eq.globalGain = 0
        for (i, freq) in defaultFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.gain = 0
            band.bandwidth = 1.0
            band.bypass = false
        }
        outEngine.attach(eq)

        // Reverb node — always in the graph. Wet/dry defaults to 0 so it's inert.
        let reverb = AVAudioUnitReverb()
        reverb.wetDryMix = 0
        outEngine.attach(reverb)
        self.reverbNode = reverb
        spatial.reverbNode = reverb

        // Visual sync delay — inserted AFTER the EQ tap so spectrum sees un-delayed audio
        // but speakers get delayed. Pure delay: 100% wet, 0 feedback, max LPF.
        let syncDelay = AVAudioUnitDelay()
        syncDelay.delayTime = TimeInterval(visualSyncSec)
        syncDelay.feedback = 0
        syncDelay.lowPassCutoff = 20000
        syncDelay.wetDryMix = 100
        outEngine.attach(syncDelay)
        self.syncDelayNode = syncDelay

        outEngine.connect(sourceNode, to: eq, format: format)
        outEngine.connect(eq, to: reverb, format: format)
        outEngine.connect(reverb, to: syncDelay, format: format)
        outEngine.connect(syncDelay, to: outEngine.mainMixerNode, format: format)

        outEngine.prepare()
        try outEngine.start()
        self.outputEngine = outEngine
        self.eq = eq
        self.sourceNode = sourceNode

        // Push current spatial settings onto the live graph
        spatial.syncInitial()
        denoise.syncInitial()


        // Tap the EQ output for the post-EQ spectrum
        let postRing = FloatRingBuffer(capacityFrames: 8192, channelCount: 2)
        self.postAnalyzerRingBuffer = postRing
        eq.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self = self,
                  let ring = self.postAnalyzerRingBuffer,
                  let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let numCh = Int(buffer.format.channelCount)
            var interleaved = [Float](repeating: 0, count: frames * numCh)
            for ch in 0..<numCh {
                let src = channels[ch]
                for f in 0..<frames {
                    interleaved[f * numCh + ch] = src[f]
                }
            }
            interleaved.withUnsafeBufferPointer { ptr in
                ring.write(src: ptr.baseAddress!, count: frames)
            }
        }

        logger.log("Output engine running on \(outputDevice.name, privacy: .public)")

        // ── Input path: HAL IOProc on BlackHole ──────────────────────
        // Using Core Audio HAL directly bypasses AVFoundation's microphone
        // permission system, so no orange "mic in use" indicator appears.
        self.blackHoleDeviceID = blackHoleID
        let analyzerRing = FloatRingBuffer(capacityFrames: 8192, channelCount: 2)
        self.analyzerRingBuffer = analyzerRing

        // Retain the context and hand the raw class pointer to Core Audio.
        // We balance the retain in teardown with Unmanaged.release().
        let context = IOProcContext(ring: ring, analyzerRing: analyzerRing)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        self.ioProcContextPtr = contextPtr

        var procID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcID(
            blackHoleID,
            etherIOProc,
            contextPtr,
            &procID
        )
        guard createStatus == noErr, let procID = procID else {
            Unmanaged<IOProcContext>.fromOpaque(contextPtr).release()
            self.ioProcContextPtr = nil
            throw EngineError.deviceSetFailed("BlackHole IOProc", createStatus)
        }
        self.blackHoleProcID = procID

        let startStatus = AudioDeviceStart(blackHoleID, procID)
        guard startStatus == noErr else {
            throw EngineError.deviceSetFailed("BlackHole IOProc start", startStatus)
        }

        // Main-thread timer: pull recent samples from analyzer ring → spectrum
        startAnalyzerTimer()

        logger.log("Pipeline active (HAL IOProc): BlackHole → EQ → \(outputDevice.name, privacy: .public)")
    }

    private var ioProcContextPtr: UnsafeMutableRawPointer?

    /// Feed BOTH analyzers every tick — pre-EQ for the ghost spectrum, post-EQ for the bright trace.
    private func startAnalyzerTimer() {
        analyzerTimer?.invalidate()
        let scratchSize = 8192  // enough for ~85ms at 48kHz stereo
        let preScratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchSize)
        let postScratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchSize)
        analyzerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Drain ALL available samples — don't cap at 512, that causes ~250ms pipeline lag
            if let pre = self.analyzerRingBuffer {
                let frames = min(scratchSize / 2, pre.availableToRead)
                if frames > 0 {
                    _ = pre.read(dst: preScratch, count: frames)
                    self.spectrum.submit(interleaved: preScratch, frameCount: frames)
                }
            }
            if let post = self.postAnalyzerRingBuffer {
                let frames = min(scratchSize / 2, post.availableToRead)
                if frames > 0 {
                    _ = post.read(dst: postScratch, count: frames)
                    self.postSpectrum.submit(interleaved: postScratch, frameCount: frames)
                    self.loudness.submit(interleaved: postScratch, frameCount: frames)
                }
            }
        }
    }

    private func teardown() {
        analyzerTimer?.invalidate()
        analyzerTimer = nil

        // HAL IOProc teardown
        if let procID = blackHoleProcID, blackHoleDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(blackHoleDeviceID, procID)
            AudioDeviceDestroyIOProcID(blackHoleDeviceID, procID)
        }
        blackHoleProcID = nil
        blackHoleDeviceID = kAudioObjectUnknown

        if let ctx = ioProcContextPtr {
            Unmanaged<IOProcContext>.fromOpaque(ctx).release()
            ioProcContextPtr = nil
        }

        analyzerRingBuffer = nil

        // Stop the post-EQ tap before detaching the EQ node
        if let eq = eq {
            eq.removeTap(onBus: 0)
        }
        postAnalyzerRingBuffer = nil

        outputEngine?.stop()
        if let eq = eq { outputEngine?.detach(eq) }
        if let s = sourceNode { outputEngine?.detach(s) }
        if let r = reverbNode { outputEngine?.detach(r) }
        outputEngine = nil
        eq = nil
        sourceNode = nil
        reverbNode = nil
        ringBuffer = nil
        stereoProcessor?.reset()
        stereoProcessor = nil
    }

    /// Swap the physical output device without stopping the engine.
    /// Rebuilds the output engine on the new device. The input engine keeps running.
    func hotSwapOutputDevice(_ newDevice: AudioDevice?) {
        guard let newDevice = newDevice, status.isRunning else { return }
        guard let outputAU = outputEngine?.outputNode.audioUnit else { return }
        do {
            try setDevice(newDevice.id, on: outputAU, label: "output")
            outputDeviceName = newDevice.name
            logger.log("Hot-swapped output to \(newDevice.name, privacy: .public)")
        } catch {
            logger.error("Hot-swap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Apply band parameters, master gain, and global bypass to the live EQ unit.
    /// Called on every drag update — lock-free, just property writes.
    /// Adaptive offsets (if active) are added on top of the user's band gains.
    func applyEQ(bands: [EQBand], masterGain: Float = 0, bypassed: Bool = false) {
        guard let eq = eq else { return }
        let adaptiveOffsets = adaptive.isActive ? adaptive.adaptiveOffsets : []
        for (i, band) in bands.enumerated() where i < eq.bands.count {
            let auBand = eq.bands[i]
            auBand.filterType = band.type.avFilterType
            auBand.frequency = band.frequency
            let offset = i < adaptiveOffsets.count ? adaptiveOffsets[i] : 0
            auBand.gain = band.type.usesGain ? max(-24, min(24, band.gain + offset)) : 0
            auBand.bandwidth = max(0.05, 1.0 / band.q)
            auBand.bypass = band.bypassed || bypassed
        }
        outputEngine?.mainMixerNode.outputVolume = pow(10, masterGain / 20)
    }

    private func setDevice(_ deviceID: AudioDeviceID, on audioUnit: AudioUnit, label: String) throws {
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &id, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw EngineError.deviceSetFailed(label, status) }
    }
}

enum EngineError: LocalizedError {
    case noAudioUnit(String)
    case deviceSetFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noAudioUnit(let n): return "Could not obtain \(n)."
        case .deviceSetFailed(let n, let c): return "Failed to set \(n) (OSStatus \(c))."
        }
    }
}
