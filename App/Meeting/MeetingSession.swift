import AudioCapture
import Foundation
import Observation
import SharedKit
import Storage
import Summarization
import SwiftData
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
        case summarizing
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var segments: [TranscriptSegment] = []
    public private(set) var startedAt: Date?

    private let modelURL: URL
    private let modelContext: ModelContext
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
    private var currentMeeting: Meeting?

    public init(modelURL: URL, modelContext: ModelContext) {
        self.modelURL = modelURL
        self.modelContext = modelContext
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
            let started = Date()
            startedAt = started

            let meeting = Meeting(
                title: defaultTitle(for: started),
                startedAt: started
            )
            modelContext.insert(meeting)
            try? modelContext.save()
            currentMeeting = meeting

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

        let endedMeeting = currentMeeting
        if let meeting = endedMeeting {
            meeting.endedAt = Date()
            try? modelContext.save()
        }

        // Generate the summary on a frozen snapshot of segments so the meeting
        // record persists even if summarization fails.
        if let meeting = endedMeeting, !segments.isEmpty {
            state = .summarizing
            await summarizeAndPersist(meeting: meeting, segments: segments)
        }

        currentMeeting = nil
    }

    private func summarizeAndPersist(meeting: Meeting, segments: [TranscriptSegment]) async {
        do {
            let summarizer = FoundationModelsSummarizer()
            let summary = try await summarizer.summarize(segments)
            attach(summary: summary, to: meeting)
            try? modelContext.save()
            Log.summary.info("Persisted summary for meeting \(meeting.id.uuidString, privacy: .public)")
        } catch SummarizationError.modelUnavailable {
            Log.summary.warning("Skipping summary — FoundationModels not available on this build")
        } catch {
            Log.summary.error("Summary generation failed: \(error.localizedDescription, privacy: .public)")
        }
        MarkdownExporter.export(meeting)
    }

    private func attach(summary: MeetingSummary, to meeting: Meeting) {
        let stored = StoredSummary(tldr: summary.tldr, decisions: summary.decisions)
        stored.meeting = meeting
        modelContext.insert(stored)

        for item in summary.actionItems {
            let storedItem = StoredActionItem(detail: item.description, assignee: item.assignee, dueDate: item.dueDate)
            storedItem.summary = stored
            modelContext.insert(storedItem)
        }
        for topic in summary.topics {
            let storedTopic = StoredTopic(title: topic.title, bullets: topic.bullets)
            storedTopic.summary = stored
            modelContext.insert(storedTopic)
        }
    }

    private func append(segment: TranscriptSegment) {
        // Keep segments ordered by start time so the UI doesn't jump around
        // when mic and system chunks finish out of order.
        let insertIndex = segments.firstIndex(where: { $0.start > segment.start }) ?? segments.endIndex
        segments.insert(segment, at: insertIndex)

        // Persist to SwiftData. The relationship inverse on `meeting` means
        // assigning here is enough — the segment auto-appears under Meeting.
        if let meeting = currentMeeting {
            let stored = StoredTranscriptSegment(
                id: segment.id,
                side: segment.side,
                start: segment.start,
                end: segment.end,
                text: segment.text
            )
            stored.meeting = meeting
            modelContext.insert(stored)
            try? modelContext.save()
        }
    }

    private func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Meeting on \(formatter.string(from: date))"
    }
}
