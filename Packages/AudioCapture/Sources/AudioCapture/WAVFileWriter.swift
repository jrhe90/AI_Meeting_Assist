import AVFoundation
import CoreMedia
import Foundation
import SharedKit

/// Writes an audio stream to a WAV file on disk and tracks total samples written.
///
/// The two capture pipelines feed buffers from different sources:
/// - AVAudioEngine (mic) emits `AVAudioPCMBuffer` directly.
/// - ScreenCaptureKit (system) emits `CMSampleBuffer`; we adapt those into a
///   matching `AVAudioPCMBuffer` before writing.
///
/// The file's sample rate and channel count are derived from the first buffer
/// we receive — AVAudioFile cannot resample or downmix as a side effect of
/// `write(from:)`, so the safe path is to record what the source produces and
/// let downstream code (whisper input, etc.) reformat as needed.
public final class WAVFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private(set) public var sampleCount: Int64 = 0
    private(set) public var actualSampleRate: Double = 0
    private(set) public var actualChannelCount: Int = 0
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private func ensureOpen(matching sourceFormat: AVAudioFormat) throws -> AVAudioFile {
        if let file { return file }

        // File format: same sample rate / channel count as the source so
        // AVAudioFile only has to convert sample depth (Float32/Int32 → Int16).
        // 16-bit signed little-endian PCM is the universally-playable WAV flavor.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sourceFormat.sampleRate,
            AVNumberOfChannelsKey: Int(sourceFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let opened = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: sourceFormat.commonFormat,
            interleaved: sourceFormat.isInterleaved
        )
        actualSampleRate = sourceFormat.sampleRate
        actualChannelCount = Int(sourceFormat.channelCount)
        file = opened
        return opened
    }

    public func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        let file = try ensureOpen(matching: buffer.format)
        try file.write(from: buffer)
        sampleCount &+= Int64(buffer.frameLength)
    }

    /// Adapts a CMSampleBuffer (from SCStream) into an AVAudioPCMBuffer and writes.
    public func write(_ sampleBuffer: CMSampleBuffer) throws {
        guard let pcm = sampleBuffer.asPCMBuffer() else {
            throw WAVFileWriterError.unsupportedSampleBuffer
        }
        try write(pcm)
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        file = nil
    }
}

public enum WAVFileWriterError: Error {
    case unsupportedSampleBuffer
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer adapter

extension CMSampleBuffer {
    /// Converts a CMSampleBuffer of audio into an AVAudioPCMBuffer.
    ///
    /// Uses `CMSampleBufferCopyPCMDataIntoAudioBufferList` rather than a manual
    /// memcpy from CMBlockBuffer — the latter scrambles channel layout for
    /// non-interleaved sources (which ScreenCaptureKit produces) and yields
    /// audible noise on playback.
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return nil }

        var asbdValue = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &asbdValue) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            Log.audio.error("CMSampleBufferCopyPCMDataIntoAudioBufferList failed status=\(status, privacy: .public)")
            return nil
        }

        return buffer
    }
}
