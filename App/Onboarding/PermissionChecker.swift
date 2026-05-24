import AVFoundation
import CoreGraphics
import Foundation
import SharedKit

/// Thin wrapper around the TCC permission APIs the onboarding wizard drives.
///
/// Mic permission goes through AVCaptureDevice. Screen-recording permission is
/// handled by CoreGraphics' `CGRequestScreenCaptureAccess` — this triggers the
/// same TCC prompt ScreenCaptureKit's `SCStream` would, so we can ask up-front
/// during onboarding rather than mid-meeting.
public enum PermissionStatus: Sendable, Hashable {
    case notDetermined
    case granted
    case denied

    public var isGranted: Bool { self == .granted }
}

@MainActor
public enum PermissionChecker {
    // MARK: Microphone

    public static func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public static func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        Log.app.info("Microphone permission request returned granted=\(granted, privacy: .public)")
        return granted ? .granted : .denied
    }

    // MARK: Screen recording

    public static func screenRecordingStatus() -> PermissionStatus {
        // CGPreflightScreenCaptureAccess() does not prompt — safe for status checks.
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    /// Triggers the system TCC prompt. The first call shows the dialog; subsequent
    /// calls return whatever the user picked. If the user denies, macOS routes them
    /// to System Settings — we cannot re-prompt from inside the app.
    public static func requestScreenRecording() -> PermissionStatus {
        let granted = CGRequestScreenCaptureAccess()
        Log.app.info("Screen recording permission request returned granted=\(granted, privacy: .public)")
        return granted ? .granted : .denied
    }
}
