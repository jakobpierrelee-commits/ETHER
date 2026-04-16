import AVFoundation
import CoreAudio
import AudioToolbox
import os

// MARK: - HAL IOProc

/// Context passed to the C IOProc callback. Contains raw ring buffer references.
final class IOProcContext {
    let ring: FloatRingBuffer
    let analyzerRing: FloatRingBuffer
    init(ring: FloatRingBuffer, analyzerRing: FloatRingBuffer) {
        self.ring = ring
        self.analyzerRing = analyzerRing
    }
}

/// C-compatible IOProc. Runs on the real-time audio thread — no allocations,
/// no locks, no Swift ARC. Just memcpy-style writes into pre-allocated rings.
private let etherIOProc: AudioDeviceIOProc = { _, _, inInputData, _, _, _, clientData in
    guard let clientData = clientData else { return noErr }
    let ctx = Unmanaged<IOProcContext>.fromOpaque(clientData).takeUnretainedValue()

    // inInputData is non-optional in the typealias but can be a list with zero buffers
    // at startup. The UnsafePointer cast is safe either way.
    let bufferList = UnsafeMutableAudioBufferListPointer(
        UnsafeMutablePointer(mutating: inInputData)
    )
    guard bufferList.count > 0,
          bufferList[0].mDataByteSize > 0,
          bufferList[0].mData != nil else { return noErr }

    // BlackHole presents either 1 interleaved buffer (2 channels) or 2 deinterleaved
    let first = bufferList[0]
    let channels = Int(first.mNumberChannels)

    if channels == 2 {
        // Interleaved: mData is L,R,L,R,...
        guard let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / 2
        ctx.ring.write(src: data, count: frames)
        ctx.analyzerRing.write(src: data, count: frames)
    } else if bufferList.count >= 2 {
        // Deinterleaved: buffer[0]=L, buffer[1]=R
        let bufL = bufferList[0]
        let bufR = bufferList[1]
        guard let dataL = bufL.mData?.assumingMemoryBound(to: Float.self),
              let dataR = bufR.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let frames = Int(bufL.mDataByteSize) / MemoryLayout<Float>.size

        // Interleave into a stack-allocated scratch of reasonable max size
        // BlackHole buffers are typically 512 frames, so 4096 is plenty.
        let maxFrames = 4096
        let copyFrames = min(frames, maxFrames)
        var scratch = [Float](repeating: 0, count: copyFrames * 2)
        for f in 0..<copyFrames {
            scratch[f * 2]     = dataL[f]
            scratch[f * 2 + 1] = dataR[f]
        }
        scratch.withUnsafeBufferPointer { ptr in
            ctx.ring.write(src: ptr.baseAddress!, count: copyFrames)
            ctx.analyzerRing.write(src: ptr.baseAddress!, count: copyFrames)
        }
    }
    return noErr
}

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

    /// The system default output device at the time Start was clicked.
    /// Restored when the engine stops.
    private var previousDefaultOutputDeviceID: AudioDeviceID?

    /// UserDefaults key for persisting the last-known-good output device UID.
    /// Used to recover if the app crashes while routed to BlackHole.
    private let lastGoodOutputKey = "audio.ether.lastGoodOutputUID"

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
        previousDefaultOutputDeviceID = currentDefaultOutputDeviceID()

        // Persist the device UID so we can recover across crashes
        if let prevID = previousDefaultOutputDeviceID,
           prevID != blackHoleID,
           let prevUID = AudioDeviceManager.deviceUID(for: prevID) {
            UserDefaults.standard.set(prevUID, forKey: lastGoodOutputKey)
        }

        // Route system audio to BlackHole so it flows through our EQ
        if !setDefaultOutputDevice(blackHoleID) {
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
                _ = setDefaultOutputDevice(previous)
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
                _ = self.setDefaultOutputDevice(previous)
                self.previousDefaultOutputDeviceID = nil
                UserDefaults.standard.removeObject(forKey: self.lastGoodOutputKey)
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
            _ = setDefaultOutputDevice(previous)
            previousDefaultOutputDeviceID = nil
            UserDefaults.standard.removeObject(forKey: lastGoodOutputKey)
        }
    }

    /// Safety net on launch: if system is currently routed to BlackHole AND we
    /// have a persisted last-good device, restore it. Handles the case where the
    /// app crashed or was force-quit while routed to BlackHole.
    func restoreOutputIfStuckOnBlackHole() {
        guard let currentID = currentDefaultOutputDeviceID(),
              let currentName = AudioDeviceManager.deviceName(for: currentID),
              currentName.contains("BlackHole") else {
            return
        }

        guard let savedUID = UserDefaults.standard.string(forKey: lastGoodOutputKey) else {
            logger.warning("System output is BlackHole but no saved device to restore to")
            return
        }

        // Find the device by UID
        for device in AudioDeviceManager.allDevices() where device.uid == savedUID {
            if setDefaultOutputDevice(device.id) {
                logger.log("Restored system output to \(device.name, privacy: .public) (was stuck on BlackHole)")
                UserDefaults.standard.removeObject(forKey: lastGoodOutputKey)
            }
            return
        }

        logger.warning("Could not find device with UID \(savedUID, privacy: .public) to restore")
    }

    // MARK: - System Default Output Routing

    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
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

    @discardableResult
    private func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
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

        outEngine.connect(sourceNode, to: eq, format: format)
        outEngine.connect(eq, to: reverb, format: format)
        outEngine.connect(reverb, to: outEngine.mainMixerNode, format: format)

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
        let preScratch = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
        let postScratch = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
        analyzerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if let pre = self.analyzerRingBuffer {
                let frames = min(512, pre.availableToRead)
                if frames > 0 {
                    _ = pre.read(dst: preScratch, count: frames)
                    self.spectrum.submit(interleaved: preScratch, frameCount: frames)
                }
            }
            if let post = self.postAnalyzerRingBuffer {
                let frames = min(512, post.availableToRead)
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
