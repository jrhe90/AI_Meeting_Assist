import Testing
@testable import SharedKit

@Test func speakerSideRawValuesAreStable() {
    #expect(SpeakerSide.me.rawValue == "me")
    #expect(SpeakerSide.others.rawValue == "others")
}
