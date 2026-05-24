import Foundation
import SharedKit

/// Public surface for dual-stream audio capture.
/// Real ScreenCaptureKit + AVAudioEngine implementations land at step 3 of §9.
public protocol AudioCapturing: AnyObject, Sendable {
    func start() async throws
    func stop() async
}

public enum AudioCaptureError: Error {
    case notImplemented
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case streamFailed(underlying: Error)
}
