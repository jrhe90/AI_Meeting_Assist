import Foundation
import SharedKit

/// Public surface for dual-stream audio capture.
/// Real ScreenCaptureKit + AVAudioEngine implementations land at step 3 of §9.
public protocol AudioCapturing: AnyObject, Sendable {
    func start() async throws
    func stop() async
}

public enum AudioCaptureError: Error, LocalizedError {
    case notImplemented
    case microphonePermissionDenied
    case noInputDeviceAvailable
    case screenRecordingPermissionDenied
    case streamFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Capture path not implemented."
        case .microphonePermissionDenied:
            return "Microphone access was denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .noInputDeviceAvailable:
            return "No audio input device is currently available. Plug in a microphone, connect AirPods, or enable your Mac's built-in mic, then try again."
        case .screenRecordingPermissionDenied:
            return "Screen recording access was denied. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .streamFailed(let underlying):
            return "Capture stream failed: \(underlying.localizedDescription)"
        }
    }
}
