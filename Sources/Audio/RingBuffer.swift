import Foundation

/// Lock-free single-producer single-consumer ring buffer for interleaved float audio.
/// Producer (installTap) writes; consumer (AVAudioSourceNode render callback) reads.
/// Safe on ARM64 because aligned 64-bit loads/stores are atomic.
final class FloatRingBuffer {
    private let buffer: UnsafeMutablePointer<Float>
    let capacityFrames: Int
    let channelCount: Int
    private var writeFrame: Int = 0
    private var readFrame: Int = 0

    init(capacityFrames: Int, channelCount: Int) {
        self.capacityFrames = capacityFrames
        self.channelCount = channelCount
        let total = capacityFrames * channelCount
        buffer = .allocate(capacity: total)
        buffer.initialize(repeating: 0, count: total)
    }

    deinit { buffer.deallocate() }

    var availableToRead: Int {
        let w = writeFrame
        let r = readFrame
        return w >= r ? w - r : capacityFrames - r + w
    }

    /// Write interleaved float samples. src must contain count * channelCount floats.
    func write(src: UnsafePointer<Float>, count: Int) {
        let w = writeFrame
        let first = min(count, capacityFrames - w)
        memcpy(buffer.advanced(by: w * channelCount),
               src,
               first * channelCount * MemoryLayout<Float>.size)
        if first < count {
            memcpy(buffer,
                   src.advanced(by: first * channelCount),
                   (count - first) * channelCount * MemoryLayout<Float>.size)
        }
        writeFrame = (w + count) % capacityFrames
    }

    /// Read interleaved float samples. dst must have space for count * channelCount floats.
    /// Returns number of frames actually read. Pads remaining with silence.
    @discardableResult
    func read(dst: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let avail = availableToRead
        let toRead = min(count, avail)
        let r = readFrame
        let first = min(toRead, capacityFrames - r)
        memcpy(dst,
               buffer.advanced(by: r * channelCount),
               first * channelCount * MemoryLayout<Float>.size)
        if first < toRead {
            memcpy(dst.advanced(by: first * channelCount),
                   buffer,
                   (toRead - first) * channelCount * MemoryLayout<Float>.size)
        }
        if toRead < count {
            memset(dst.advanced(by: toRead * channelCount),
                   0,
                   (count - toRead) * channelCount * MemoryLayout<Float>.size)
        }
        readFrame = (r + toRead) % capacityFrames
        return toRead
    }
}
