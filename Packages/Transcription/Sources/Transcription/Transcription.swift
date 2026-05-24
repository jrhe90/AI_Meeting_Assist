import Foundation
import SharedKit

/// A finalized chunk of transcribed speech, tagged with the capture side.
public struct TranscriptSegment: Hashable, Sendable, Codable {
    public let id: UUID
    public let side: SpeakerSide
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(
        id: UUID = UUID(),
        side: SpeakerSide,
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) {
        self.id = id
        self.side = side
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Real whisper.cpp bridge lands at step 4 of §9.
public protocol Transcribing: AnyObject, Sendable {
    func transcribe(wavURL: URL, side: SpeakerSide) async throws -> [TranscriptSegment]
}

public enum TranscriptionError: Error {
    case modelNotInstalled
    case loadFailed(reason: String)
    case decodeFailed(reason: String)
}
