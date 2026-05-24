import Foundation
import Transcription

/// Real FoundationModels-backed implementation lands at step 7 of §9.
/// Hierarchical chunking (§10.2) is layered on at step 8.
public protocol Summarizing: AnyObject, Sendable {
    func summarize(_ segments: [TranscriptSegment]) async throws -> MeetingSummary
}

public enum SummarizationError: Error {
    case modelUnavailable
    case contextOverflow
    case generationFailed(reason: String)
}
