import Foundation
import FoundationModels
import SharedKit
import Transcription

/// `@Generable` projection of `MeetingSummary` used by guided generation.
///
/// Kept separate from `MeetingSummary` so the rest of the codebase (Storage,
/// UI) can depend on a plain-value type without importing FoundationModels.
@Generable
public struct GeneratedMeetingSummary {
    @Guide(description: "1-3 sentence high-level overview of what the meeting was about and what was concluded.")
    public var tldr: String

    @Guide(description: "Concrete decisions reached during the meeting. Each entry is one decision, phrased as a complete sentence. Empty if none.")
    public var decisions: [String]

    @Guide(description: "Tasks or follow-ups that someone agreed to do, with best-effort assignee and due date pulled from the transcript.")
    public var actionItems: [GeneratedActionItem]

    @Guide(description: "Topics discussed during the meeting. Each topic groups related conversation under a short title and 2-5 bullet points.")
    public var topics: [GeneratedTopic]
}

@Generable
public struct GeneratedActionItem {
    @Guide(description: "What needs to be done, phrased as an imperative sentence.")
    public var detail: String

    @Guide(description: "Person responsible if mentioned in the transcript. Use null when unclear.")
    public var assignee: String?

    @Guide(description: "Due date if mentioned (free-form, e.g. 'next Friday' or '2026-05-30'). Use null when unclear.")
    public var dueDate: String?
}

@Generable
public struct GeneratedTopic {
    @Guide(description: "Short title for the topic, 2-6 words.")
    public var title: String

    @Guide(description: "2-5 bullet points capturing what was said about this topic.")
    public var bullets: [String]
}

/// Drives on-device summarization through Apple's FoundationModels.
///
/// On macOS 26 Tahoe builds where the system language model isn't yet
/// available (developer device without the OS model installed, beta channel
/// without entitlement, etc.) `summarize` throws `SummarizationError.modelUnavailable`
/// so the meeting still finalises cleanly without a summary.
public final class FoundationModelsSummarizer: Summarizing {
    public init() {}

    public func summarize(_ segments: [TranscriptSegment]) async throws -> MeetingSummary {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            Log.summary.warning("FoundationModels unavailable: \(String(describing: reason), privacy: .public)")
            throw SummarizationError.modelUnavailable
        @unknown default:
            throw SummarizationError.modelUnavailable
        }

        let transcript = Self.formatTranscript(segments)
        guard !transcript.isEmpty else {
            // Empty transcript still yields a clean summary so the meeting
            // detail view doesn't crash when opened.
            return MeetingSummary(tldr: "No speech was captured.", decisions: [], actionItems: [], topics: [])
        }

        let instructions = """
        You are a careful note-taker summarizing a meeting transcript. The
        transcript is tagged with [Me] (this user's microphone) and [Others]
        (system audio — anything from other participants or video calls).
        Produce a structured summary. Be specific; cite what was actually
        said rather than generalising. If a category has nothing to put in
        it, return an empty list.
        """

        let session = LanguageModelSession(model: model, instructions: instructions)

        do {
            let response = try await session.respond(
                to: "Summarize the following meeting transcript:\n\n\(transcript)",
                generating: GeneratedMeetingSummary.self
            )
            return Self.translate(response.content)
        } catch {
            Log.summary.error("FoundationModels respond failed: \(error.localizedDescription, privacy: .public)")
            throw SummarizationError.generationFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func formatTranscript(_ segments: [TranscriptSegment]) -> String {
        segments
            .sorted { $0.start < $1.start }
            .map { seg -> String in
                let tag = seg.side == .me ? "Me" : "Others"
                let ts = String(format: "%02d:%02d", Int(seg.start) / 60, Int(seg.start) % 60)
                return "[\(ts) \(tag)] \(seg.text)"
            }
            .joined(separator: "\n")
    }

    private static func translate(_ generated: GeneratedMeetingSummary) -> MeetingSummary {
        MeetingSummary(
            tldr: generated.tldr,
            decisions: generated.decisions,
            actionItems: generated.actionItems.map {
                ActionItem(description: $0.detail, assignee: $0.assignee, dueDate: $0.dueDate)
            },
            topics: generated.topics.map { Topic(title: $0.title, bullets: $0.bullets) }
        )
    }
}
