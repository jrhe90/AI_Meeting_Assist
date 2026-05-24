import AVFoundation
import Foundation
import SharedKit

/// Streams transcription off a live PCM source.
///
/// Buffers samples internally (already converted to whisper's 16 kHz mono
/// Float32 format), slices a fixed-size chunk every `chunkDuration` seconds,
/// and runs it through `WhisperEngine`. Segments are emitted via `segments`,
/// an `AsyncStream` the caller iterates.
///
/// The actor itself only handles `[Float]` samples — format conversion is
/// done by a separate `PCMResampler` helper on the audio-capture thread,
/// keeping AVAudioPCMBuffer (non-Sendable) off the actor boundary.
///
/// Hierarchical chunking from §10.2 lives at a higher layer; this actor only
/// knows about the live windowing. Whisper hallucinations on silence (§10.4)
/// are gated by a simple RMS threshold.
public actor StreamingTranscriber {
    private let engine: WhisperEngine
    private let side: SpeakerSide
    private let chunkDurationSamples: Int
    private let silenceRMSThreshold: Float

    private var buffer: [Float] = []
    private var chunkOffsetSeconds: TimeInterval = 0

    public nonisolated let segments: AsyncStream<TranscriptSegment>
    private let continuation: AsyncStream<TranscriptSegment>.Continuation

    public init(
        engine: WhisperEngine,
        side: SpeakerSide,
        chunkDuration: TimeInterval = 10,
        silenceRMSThreshold: Float = 0.003
    ) {
        self.engine = engine
        self.side = side
        self.chunkDurationSamples = Int(chunkDuration * 16_000)
        self.silenceRMSThreshold = silenceRMSThreshold
        (self.segments, self.continuation) = AsyncStream.makeStream(of: TranscriptSegment.self)
    }

    /// Append already-resampled 16 kHz mono Float32 samples. Triggers
    /// transcription whenever the buffer crosses the chunk threshold.
    public func ingest(samples: [Float]) {
        buffer.append(contentsOf: samples)

        while buffer.count >= chunkDurationSamples {
            let chunk = Array(buffer.prefix(chunkDurationSamples))
            buffer.removeFirst(chunkDurationSamples)
            let offset = chunkOffsetSeconds
            chunkOffsetSeconds += TimeInterval(chunkDurationSamples) / 16_000.0
            scheduleTranscription(chunk: chunk, offset: offset)
        }
    }

    /// Flush any partial buffer that hasn't yet hit the chunk threshold and
    /// close the segments stream.
    public func finish() async {
        if !buffer.isEmpty {
            let chunk = buffer
            buffer.removeAll()
            let offset = chunkOffsetSeconds
            chunkOffsetSeconds += TimeInterval(chunk.count) / 16_000.0
            await transcribe(chunk: chunk, offset: offset)
        }
        continuation.finish()
    }

    // MARK: - Internals

    private func scheduleTranscription(chunk: [Float], offset: TimeInterval) {
        Task { await self.transcribe(chunk: chunk, offset: offset) }
    }

    private func transcribe(chunk: [Float], offset: TimeInterval) async {
        guard rms(chunk) >= silenceRMSThreshold else { return }
        do {
            let produced = try await engine.transcribeRaw(samples: chunk, side: side, baseTime: offset)
            for seg in produced { continuation.yield(seg) }
        } catch {
            Log.whisper.error("Stream chunk failed at offset \(offset, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}

/// Thread-safe wrapper around AVAudioConverter that downsamples / downmixes
/// audio-capture buffers to whisper's 16 kHz mono Float32 format.
///
/// Used inside the audio-thread buffer handlers; the synchronous conversion
/// of ~4k-sample buffers is well within the real-time budget. Keeps the
/// non-Sendable AVAudioPCMBuffer off the StreamingTranscriber actor boundary.
public final class PCMResampler: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }

        let inFormat = buffer.format

        if converter == nil || sourceFormat != inFormat {
            guard let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            ) else { return nil }
            guard let c = AVAudioConverter(from: inFormat, to: target) else { return nil }
            converter = c
            sourceFormat = inFormat
        }
        guard let converter else { return nil }

        // AVAudioConverter accumulates state across calls; signalling
        // `.endOfStream` (as we do below for a one-shot batch convert) puts
        // the converter into a "finished" state. We have to reset it before
        // every buffer or subsequent conversions return no data.
        converter.reset()

        let ratio = converter.outputFormat.sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var consumed = false
        var convertError: NSError?
        let status = converter.convert(to: out, error: &convertError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let convertError {
            Log.whisper.error("PCMResampler convert failed: \(convertError.localizedDescription, privacy: .public)")
            return nil
        }
        guard status != .error else {
            Log.whisper.error("PCMResampler convert returned .error status")
            return nil
        }

        guard let channel = out.floatChannelData?[0] else {
            Log.whisper.error("PCMResampler output has no float channel data")
            return nil
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}
