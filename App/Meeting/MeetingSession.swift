import AudioCapture
import Foundation
import Observation
import SharedKit
import Transcription

/// Drives a live meeting: spins up both capture pipelines, pipes their PCM
/// buffers into per-side StreamingTranscribers, and exposes a merged list of
/// transcript segments that the UI can observe.
///
/// On macOS where no mic is available (or the user opts out), runs in
/// system-only mode — the Me side stays empty.
@MainActor
@Observable
public final class MeetingSession {
    public enum State: Sendable, Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var segments: [TranscriptSegment] = []
    public private(set) var startedAt: Date?

    private let modelURL: URL
    private let mic = MicCapture()
    private let system = SystemAudioCapture()
    private var engine: WhisperEngine?
    private var micStreamer: StreamingTranscriber?
    private var systemStreamer: StreamingTranscriber?
    private var micConsumer: Task<Void, Never>?
    private var systemConsumer: Task<Void, Never>?
    private var hasMic: Bool = false
    private let micResampler = PCMResampler()
    private let systemResampler = PCMResampler()

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    public func start() {
        guard state == .idle else { return }
        state = .starting
        Task { await self.startInternal() }
    }

    public func stop() {
        guard state == .running else { return }
        state = .stopping
        Task { await self.stopInternal() }
    }

    // MARK: - Lifecycle

    private func startInternal() async {
        do {
            segments.removeAll()
            startedAt = Date()

            let engine = WhisperEngine(modelURL: modelURL)
            try await engine.load()
            self.engine = engine

            let systemStreamer = StreamingTranscriber(engine: engine, side: .others)
            self.systemStreamer = systemStreamer
            let systemResampler = self.systemResampler
            try await system.start { [systemStreamer, systemResampler] buffer in
                guard let samples = systemResampler.convert(buffer) else { return }
                Task { await systemStreamer.ingest(samples: samples) }
            }
            systemConsumer = Task { [weak self] in
                for await seg in systemStreamer.segments {
                    await self?.append(segment: seg)
                }
            }

            // Mic is best-effort. If no device is available we degrade
            // to system-only rather than failing the whole meeting.
            let micStreamer = StreamingTranscriber(engine: engine, side: .me)
            let micResampler = self.micResampler
            do {
                try await mic.start { [micStreamer, micResampler] buffer in
                    guard let samples = micResampler.convert(buffer) else { return }
                    Task { await micStreamer.ingest(samples: samples) }
                }
                self.micStreamer = micStreamer
                hasMic = true
                micConsumer = Task { [weak self] in
                    for await seg in micStreamer.segments {
                        await self?.append(segment: seg)
                    }
                }
            } catch {
                Log.app.warning("Meeting starting without mic: \(error.localizedDescription, privacy: .public)")
                hasMic = false
            }

            state = .running
        } catch {
            await teardown()
            state = .error(error.localizedDescription)
        }
    }

    private func stopInternal() async {
        await teardown()
        state = .idle
    }

    private func teardown() async {
        try? await system.stop()
        if hasMic { try? await mic.stop() }

        if let s = systemStreamer { await s.finish() }
        if let m = micStreamer { await m.finish() }

        systemConsumer?.cancel()
        micConsumer?.cancel()

        systemStreamer = nil
        micStreamer = nil
        systemConsumer = nil
        micConsumer = nil
        engine = nil
        hasMic = false
    }

    private func append(segment: TranscriptSegment) {
        // Keep segments ordered by start time so the UI doesn't jump around
        // when mic and system chunks finish out of order.
        let insertIndex = segments.firstIndex(where: { $0.start > segment.start }) ?? segments.endIndex
        segments.insert(segment, at: insertIndex)
    }
}
