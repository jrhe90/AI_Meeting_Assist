import AVFoundation
import Foundation
import SharedKit
import whisper

/// Thin Swift wrapper around whisper.cpp.
///
/// Loads a ggml/gguf model file once, then transcribes WAV files into
/// `[TranscriptSegment]`. Audio is resampled to whisper's required format —
/// 16 kHz mono Float32 — via `AVAudioConverter` before being handed to
/// `whisper_full`.
public actor WhisperEngine: Transcribing {
    private var ctx: OpaquePointer?
    private let modelURL: URL

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    isolated deinit {
        if let ctx { whisper_free(ctx) }
    }

    public func load() throws {
        guard ctx == nil else { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelNotInstalled
        }

        var params = whisper_context_default_params()
        params.use_gpu = true

        let path = modelURL.path
        let loaded = path.withCString { whisper_init_from_file_with_params($0, params) }
        guard let loaded else {
            throw TranscriptionError.loadFailed(reason: "whisper_init_from_file_with_params returned null for \(modelURL.lastPathComponent)")
        }
        ctx = loaded
        Log.whisper.info("Loaded whisper model: \(self.modelURL.lastPathComponent, privacy: .public)")
    }

    public func transcribe(wavURL: URL, side: SpeakerSide) async throws -> [TranscriptSegment] {
        if ctx == nil { try load() }
        guard let ctx else { throw TranscriptionError.loadFailed(reason: "context unavailable after load") }

        let pcm = try Self.readAndResample(url: wavURL)
        Log.whisper.info("Transcribing \(wavURL.lastPathComponent, privacy: .public): \(pcm.count, privacy: .public) samples at 16kHz")

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_context = true
        params.suppress_blank = true
        params.language = ("en" as NSString).utf8String

        let status = pcm.withUnsafeBufferPointer { buf -> Int32 in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard status == 0 else {
            throw TranscriptionError.decodeFailed(reason: "whisper_full returned \(status)")
        }

        let nSegments = whisper_full_n_segments(ctx)
        var segments: [TranscriptSegment] = []
        segments.reserveCapacity(Int(nSegments))
        for i in 0..<nSegments {
            let t0 = whisper_full_get_segment_t0(ctx, i)  // centiseconds
            let t1 = whisper_full_get_segment_t1(ctx, i)
            let text = String(cString: whisper_full_get_segment_text(ctx, i))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            segments.append(TranscriptSegment(
                side: side,
                start: TimeInterval(t0) / 100.0,
                end: TimeInterval(t1) / 100.0,
                text: text
            ))
        }
        Log.whisper.info("Produced \(segments.count, privacy: .public) segments")
        return segments
    }

    // MARK: - Audio decoding

    /// Decodes a WAV file (any sample rate / channel layout AVAudioFile can
    /// open) into 16 kHz mono Float32 samples, which is what whisper expects.
    nonisolated private static func readAndResample(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw TranscriptionError.decodeFailed(reason: "could not create 16kHz mono float32 format")
        }

        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        guard let converter else {
            throw TranscriptionError.decodeFailed(reason: "no converter from \(sourceFormat) to \(targetFormat)")
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TranscriptionError.decodeFailed(reason: "input buffer allocation failed")
        }
        try file.read(into: inputBuffer)

        // Output frame count scales by the sample-rate ratio. Add a little
        // headroom since AVAudioConverter rounds.
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw TranscriptionError.decodeFailed(reason: "output buffer allocation failed")
        }

        var consumed = false
        var convertError: NSError?
        let status = converter.convert(to: outputBuffer, error: &convertError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        if let convertError {
            throw TranscriptionError.decodeFailed(reason: "AVAudioConverter: \(convertError.localizedDescription)")
        }
        guard status != .error else {
            throw TranscriptionError.decodeFailed(reason: "AVAudioConverter returned error status")
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw TranscriptionError.decodeFailed(reason: "output buffer has no float channel data")
        }
        let count = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: count))
    }
}
