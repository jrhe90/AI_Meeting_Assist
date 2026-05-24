import Foundation

// NOTE: `@Generable` types live in the FoundationModels framework, which is
// only available on macOS 26 Tahoe. We declare the plain-value mirror of the
// schema here so the rest of the codebase (Storage, UI) can depend on these
// types without importing FoundationModels. The `@Generable` projection is
// added in a `FoundationModelsSummarizer.swift` file at step 7 of §9.

public struct MeetingSummary: Hashable, Sendable, Codable {
    public var tldr: String
    public var decisions: [String]
    public var actionItems: [ActionItem]
    public var topics: [Topic]

    public init(
        tldr: String,
        decisions: [String],
        actionItems: [ActionItem],
        topics: [Topic]
    ) {
        self.tldr = tldr
        self.decisions = decisions
        self.actionItems = actionItems
        self.topics = topics
    }
}

public struct ActionItem: Hashable, Sendable, Codable {
    public var description: String
    public var assignee: String?
    public var dueDate: String?

    public init(description: String, assignee: String? = nil, dueDate: String? = nil) {
        self.description = description
        self.assignee = assignee
        self.dueDate = dueDate
    }
}

public struct Topic: Hashable, Sendable, Codable {
    public var title: String
    public var bullets: [String]

    public init(title: String, bullets: [String]) {
        self.title = title
        self.bullets = bullets
    }
}
