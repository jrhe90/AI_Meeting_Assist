import Foundation

/// Which capture stream a transcript segment came from.
/// The cheap diarization in §5 maps mic → .me and system → .others.
public enum SpeakerSide: String, Codable, Sendable, CaseIterable {
    case me
    case others
}
