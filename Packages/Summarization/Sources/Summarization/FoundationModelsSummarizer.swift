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
    /// Rough character budget per chunk. The on-device model context is
    /// nominally ~4 k tokens — keeping each chunk under ~3 000 characters
    /// (~750 tokens) leaves plenty of room for instructions and the
    /// @Generable schema overhead.
    private let chunkCharBudget: Int

    public init(chunkCharBudget: Int = 3_000) {
        self.chunkCharBudget = chunkCharBudget
    }

    public func summarize(_ segments: [TranscriptSegment]) async throws -> MeetingSummary {
        try Self.assertModelAvailable()

        let sorted = segments.sorted { $0.start < $1.start }
        let chunks = Self.chunk(sorted, charBudget: chunkCharBudget)
        let language = Self.detectLanguage(in: sorted)
        Log.summary.info("Summarizing \(sorted.count, privacy: .public) segments in \(chunks.count, privacy: .public) chunk(s), language=\(language.rawValue, privacy: .public)")

        guard !chunks.isEmpty else {
            return MeetingSummary(tldr: "No speech was captured.", decisions: [], actionItems: [], topics: [])
        }

        if chunks.count == 1 {
            return try await summarizeChunk(chunks[0], language: language)
        }

        // Hierarchical: summarize each chunk, then ask the model to merge
        // the partials. Keeps each FM call comfortably under the context window.
        var partials: [MeetingSummary] = []
        partials.reserveCapacity(chunks.count)
        for (index, chunk) in chunks.enumerated() {
            Log.summary.info("Summarizing chunk \(index + 1, privacy: .public)/\(chunks.count, privacy: .public)")
            let partial = try await summarizeChunk(chunk, language: language)
            partials.append(partial)
        }
        return try await mergePartials(partials, language: language)
    }

    // MARK: - Chunk-level summarization

    private func summarizeChunk(_ segments: [TranscriptSegment], language: TranscriptLanguage) async throws -> MeetingSummary {
        let transcript = Self.formatTranscript(segments)
        guard !transcript.isEmpty else {
            return MeetingSummary(tldr: "", decisions: [], actionItems: [], topics: [])
        }

        let instructions = """
        \(language.responseInstruction)

        You are a careful note-taker summarizing a meeting transcript. The
        transcript is tagged with [Me] (this user's microphone) and [Others]
        (system audio — anything from other participants or video calls).
        Produce a structured summary. Be specific; cite what was actually
        said rather than generalising. If a category has nothing to put in
        it, return an empty list.

        All fields you produce (tldr, decisions, action items, topics,
        bullets) MUST be written in the same language as the transcript:
        \(language.humanName).
        """

        let session = LanguageModelSession(model: .default, instructions: instructions)

        do {
            let response = try await session.respond(
                to: """
                Summarize the following meeting transcript. Reply entirely in \(language.humanName).

                \(transcript)
                """,
                generating: GeneratedMeetingSummary.self
            )
            return Self.translate(response.content)
        } catch {
            Log.summary.error("FoundationModels respond failed: \(error.localizedDescription, privacy: .public)")
            throw SummarizationError.generationFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Merging partial summaries

    private func mergePartials(_ partials: [MeetingSummary], language: TranscriptLanguage) async throws -> MeetingSummary {
        let prompt = Self.formatPartialSummaries(partials)

        let instructions = """
        \(language.responseInstruction)

        You are merging partial summaries of one meeting that was processed
        in chunks. Produce a single unified summary: combine the chunk
        TL;DRs into a coherent 1-3 sentence overview, deduplicate decisions
        and action items, and merge topics that overlap (similar titles or
        bullets) while preserving distinct ones. Do not invent content that
        is not present in the partial summaries.

        All fields you produce MUST be written in \(language.humanName).
        """

        let session = LanguageModelSession(model: .default, instructions: instructions)

        do {
            let response = try await session.respond(
                to: """
                Merge these partial summaries into one final meeting summary. Reply entirely in \(language.humanName).

                \(prompt)
                """,
                generating: GeneratedMeetingSummary.self
            )
            return Self.translate(response.content)
        } catch {
            Log.summary.error("Merge step failed, falling back to naive union: \(error.localizedDescription, privacy: .public)")
            // Best-effort fallback so the user still gets *something* if the
            // merge call fails — concatenate TL;DRs, union the rest.
            return Self.naiveMerge(partials)
        }
    }

    private static func naiveMerge(_ partials: [MeetingSummary]) -> MeetingSummary {
        let tldr = partials.map(\.tldr).filter { !$0.isEmpty }.joined(separator: " ")
        let decisions = Array(NSOrderedSet(array: partials.flatMap(\.decisions))) as? [String] ?? []
        let actionItems = partials.flatMap(\.actionItems)
        let topics = partials.flatMap(\.topics)
        return MeetingSummary(
            tldr: tldr,
            decisions: decisions,
            actionItems: actionItems,
            topics: topics
        )
    }

    // MARK: - Helpers

    /// Rough script-based detection of the transcript's dominant language so
    /// we can ask Foundation Models to respond in kind. Counts characters by
    /// Unicode block: CJK ideographs → Chinese, hiragana/katakana → Japanese,
    /// Hangul → Korean, Cyrillic → Russian, otherwise default to English.
    /// Good enough to pick the right response language; not a real classifier.
    enum TranscriptLanguage: String, Sendable {
        case english
        case chinese
        case japanese
        case korean
        case russian

        var responseInstruction: String {
            switch self {
            case .english:  return "Respond in English."
            case .chinese:  return "IMPORTANT: Respond entirely in Simplified Chinese. 请用简体中文回答所有内容，包括标题、要点、决定和任务。不要使用任何英文。"
            case .japanese: return "IMPORTANT: Respond entirely in Japanese. すべての回答を日本語で書いてください。タイトル、要点、決定事項、アクション項目を含めて、英語は使わないでください。"
            case .korean:   return "IMPORTANT: Respond entirely in Korean. 모든 답변을 한국어로 작성하세요. 제목, 요점, 결정 사항, 작업 항목을 포함하여 영어를 사용하지 마세요."
            case .russian:  return "IMPORTANT: Respond entirely in Russian. Все ответы должны быть на русском языке."
            }
        }

        var humanName: String {
            switch self {
            case .english:  return "English"
            case .chinese:  return "Simplified Chinese (简体中文)"
            case .japanese: return "Japanese (日本語)"
            case .korean:   return "Korean (한국어)"
            case .russian:  return "Russian (русский)"
            }
        }
    }

    static func detectLanguage(in segments: [TranscriptSegment]) -> TranscriptLanguage {
        var counts: [TranscriptLanguage: Int] = [:]
        for segment in segments {
            for scalar in segment.text.unicodeScalars {
                let v = scalar.value
                switch v {
                // CJK Unified Ideographs (basic block) + Extension A.
                case 0x4E00...0x9FFF, 0x3400...0x4DBF:
                    counts[.chinese, default: 0] += 1
                // Hiragana + Katakana.
                case 0x3040...0x309F, 0x30A0...0x30FF:
                    counts[.japanese, default: 0] += 1
                // Hangul syllables + Jamo.
                case 0xAC00...0xD7AF, 0x1100...0x11FF:
                    counts[.korean, default: 0] += 1
                // Cyrillic (basic + supplement).
                case 0x0400...0x04FF, 0x0500...0x052F:
                    counts[.russian, default: 0] += 1
                default:
                    break
                }
            }
        }
        // Japanese mixes hiragana/katakana with CJK; if both are present and
        // there are any kana, call it Japanese.
        if (counts[.japanese] ?? 0) > 0 { return .japanese }
        return counts.max(by: { $0.value < $1.value })?.key ?? .english
    }

    private static func assertModelAvailable() throws {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return
        case .unavailable(let reason):
            Log.summary.warning("FoundationModels unavailable: \(String(describing: reason), privacy: .public)")
            throw SummarizationError.modelUnavailable
        @unknown default:
            throw SummarizationError.modelUnavailable
        }
    }

    private static func formatTranscript(_ segments: [TranscriptSegment]) -> String {
        segments.map { seg -> String in
            let tag = seg.side == .me ? "Me" : "Others"
            let ts = String(format: "%02d:%02d", Int(seg.start) / 60, Int(seg.start) % 60)
            return "[\(ts) \(tag)] \(seg.text)"
        }
        .joined(separator: "\n")
    }

    private static func formatPartialSummaries(_ partials: [MeetingSummary]) -> String {
        partials.enumerated().map { (index, partial) -> String in
            var lines: [String] = []
            lines.append("--- Partial \(index + 1) ---")
            if !partial.tldr.isEmpty { lines.append("TL;DR: \(partial.tldr)") }
            if !partial.decisions.isEmpty {
                lines.append("Decisions:")
                for d in partial.decisions { lines.append("- \(d)") }
            }
            if !partial.actionItems.isEmpty {
                lines.append("Action items:")
                for a in partial.actionItems {
                    var line = "- \(a.description)"
                    if let assignee = a.assignee, !assignee.isEmpty { line += " (owner: \(assignee))" }
                    if let due = a.dueDate, !due.isEmpty { line += " (due: \(due))" }
                    lines.append(line)
                }
            }
            if !partial.topics.isEmpty {
                lines.append("Topics:")
                for t in partial.topics {
                    lines.append("- \(t.title)")
                    for b in t.bullets { lines.append("  • \(b)") }
                }
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// Splits sorted segments into chunks whose formatted-transcript length
    /// stays under `charBudget`. A single oversized segment lands in its own
    /// chunk rather than being split — that keeps timestamps intact.
    private static func chunk(_ segments: [TranscriptSegment], charBudget: Int) -> [[TranscriptSegment]] {
        guard !segments.isEmpty else { return [] }

        var chunks: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        var currentChars = 0

        for seg in segments {
            let segChars = formatSegmentLength(seg)
            if !current.isEmpty && currentChars + segChars > charBudget {
                chunks.append(current)
                current = []
                currentChars = 0
            }
            current.append(seg)
            currentChars += segChars
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func formatSegmentLength(_ seg: TranscriptSegment) -> Int {
        // Mirror of formatTranscript's per-segment output:
        // "[mm:ss Tag] text\n"  — 12 chars of framing + text length.
        12 + seg.text.count
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
