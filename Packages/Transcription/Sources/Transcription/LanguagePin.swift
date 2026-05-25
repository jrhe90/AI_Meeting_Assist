import Foundation

/// First-detection-wins language lock, shared across the two
/// `StreamingTranscriber` instances of a single meeting.
///
/// The first chunk that produces a detected language sets the pin; every
/// subsequent chunk on either side reads the pin and tells whisper to use
/// that language explicitly, which is both faster (skips auto-detect) and
/// more accurate than re-detecting on each 10-second chunk.
public final class LanguagePin: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    public init() {}

    public var code: String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    /// Set the pin if it hasn't been set yet. Safe to call from any side.
    public func setIfEmpty(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if stored == nil { stored = trimmed }
    }
}
