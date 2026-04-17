import CoreAudio
import AudioToolbox

// MARK: - HAL IOProc
//
// Raw Core Audio I/O callback for reading audio from BlackHole.
// Runs on the real-time audio thread — no allocations, no locks, no Swift ARC.
// Memcpy-style writes into pre-allocated ring buffers.

/// Context passed to the C IOProc callback. Contains raw ring buffer references.
final class IOProcContext {
    let ring: FloatRingBuffer
    let analyzerRing: FloatRingBuffer
    init(ring: FloatRingBuffer, analyzerRing: FloatRingBuffer) {
        self.ring = ring
        self.analyzerRing = analyzerRing
    }
}

/// C-compatible IOProc. Reads BlackHole's input buffer (either interleaved 2ch
/// or deinterleaved L/R) and writes interleaved stereo into both ring buffers.
let etherIOProc: AudioDeviceIOProc = { _, _, inInputData, _, _, _, clientData in
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
