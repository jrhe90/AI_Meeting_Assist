import Testing
@testable import Summarization

@Test func summaryRoundTripsThroughCodable() throws {
    let summary = MeetingSummary(
        tldr: "We agreed to ship v1 in May.",
        decisions: ["Use whisper small.en as default"],
        actionItems: [ActionItem(description: "File notarization ticket", assignee: "Me", dueDate: nil)],
        topics: [Topic(title: "Roadmap", bullets: ["v1 menubar app", "v2 calendar detect"])]
    )
    let data = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(MeetingSummary.self, from: data)
    #expect(decoded == summary)
}
