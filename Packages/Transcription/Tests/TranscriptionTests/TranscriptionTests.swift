import Testing
@testable import Transcription
import SharedKit

@Test func segmentRoundTripsThroughCodable() throws {
    let segment = TranscriptSegment(side: .me, start: 0, end: 1.5, text: "hello")
    let data = try JSONEncoder().encode(segment)
    let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
    #expect(decoded == segment)
}
