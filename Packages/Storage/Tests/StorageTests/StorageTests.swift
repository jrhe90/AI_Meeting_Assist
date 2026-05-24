import Testing
@testable import Storage
import Foundation

@Test func meetingInitializerDefaults() {
    let meeting = Meeting(title: "Standup")
    #expect(meeting.title == "Standup")
    #expect(meeting.endedAt == nil)
}
