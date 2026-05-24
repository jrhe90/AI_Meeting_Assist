import Foundation
import SharedKit
import SwiftData

/// Top-level meeting record. Owns its transcript segments and (eventually)
/// a single summary. The optional `endedAt` lets us distinguish a meeting
/// that's currently recording from one that's been finalised.
@Model
public final class Meeting {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StoredTranscriptSegment.meeting)
    public var segments: [StoredTranscriptSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \StoredSummary.meeting)
    public var summary: StoredSummary?

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = .now,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// One transcribed segment of speech, tagged with the capture side
/// (mic = .me, system = .others). `start` / `end` are seconds from the
/// meeting's startedAt — they line up with whisper's segment timestamps.
@Model
public final class StoredTranscriptSegment {
    public var id: UUID
    public var sideRaw: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public var meeting: Meeting?

    public var side: SpeakerSide {
        get { SpeakerSide(rawValue: sideRaw) ?? .others }
        set { sideRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        side: SpeakerSide,
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) {
        self.id = id
        self.sideRaw = side.rawValue
        self.start = start
        self.end = end
        self.text = text
    }
}

/// One meeting's structured summary. Mirrors the plain-value
/// `MeetingSummary` shape from the Summarization package; we keep two types
/// because SwiftData @Models can't be Codable structs.
@Model
public final class StoredSummary {
    public var id: UUID
    public var tldr: String
    public var decisions: [String]
    public var generatedAt: Date

    public var meeting: Meeting?

    @Relationship(deleteRule: .cascade, inverse: \StoredActionItem.summary)
    public var actionItems: [StoredActionItem] = []

    @Relationship(deleteRule: .cascade, inverse: \StoredTopic.summary)
    public var topics: [StoredTopic] = []

    public init(
        id: UUID = UUID(),
        tldr: String,
        decisions: [String] = [],
        generatedAt: Date = .now
    ) {
        self.id = id
        self.tldr = tldr
        self.decisions = decisions
        self.generatedAt = generatedAt
    }
}

@Model
public final class StoredActionItem {
    public var id: UUID
    public var detail: String
    public var assignee: String?
    public var dueDate: String?

    public var summary: StoredSummary?

    public init(id: UUID = UUID(), detail: String, assignee: String? = nil, dueDate: String? = nil) {
        self.id = id
        self.detail = detail
        self.assignee = assignee
        self.dueDate = dueDate
    }
}

@Model
public final class StoredTopic {
    public var id: UUID
    public var title: String
    public var bullets: [String]

    public var summary: StoredSummary?

    public init(id: UUID = UUID(), title: String, bullets: [String] = []) {
        self.id = id
        self.title = title
        self.bullets = bullets
    }
}

/// Schema entry-point for the app's `ModelContainer`. Use this so the App
/// target doesn't have to enumerate every @Model class itself.
public enum StorageSchema {
    public static let models: [any PersistentModel.Type] = [
        Meeting.self,
        StoredTranscriptSegment.self,
        StoredSummary.self,
        StoredActionItem.self,
        StoredTopic.self
    ]
}
