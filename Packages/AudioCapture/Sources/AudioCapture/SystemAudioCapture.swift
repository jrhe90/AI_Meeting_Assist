import AVFoundation
import Foundation
import ScreenCaptureKit
import SharedKit

/// Captures system audio (everything playing through the default output device,
/// minus this app's own audio) via ScreenCaptureKit and delivers PCM buffers
/// to a caller-supplied handler.
///
/// We use SCStream in audio-only mode: a real-time SCStreamOutput receiver
/// pulls CMSampleBuffers off the stream, adapts them into AVAudioPCMBuffers,
/// and hands them to the handler.
public actor SystemAudioCapture {
    private var stream: SCStream?
    private var receiver: AudioOutputReceiver?
    private var isRunning = false

    public init() {}

    public func start(handler: @escaping AudioBufferHandler) async throws {
        guard !isRunning else { return }

        // Resolve a content filter. We need *some* display to attach the stream
        // to even though we only care about audio; pick the first display.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw AudioCaptureError.screenRecordingPermissionDenied
        }

        guard let display = content.displays.first else {
            throw AudioCaptureError.streamFailed(underlying: SystemAudioCaptureError.noDisplays)
        }

        // Exclude our own bundle so we don't pick up our own UI sounds / audio.
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Video is required by SCStream but we don't consume it — keep the
        // resolution tiny and the frame rate as low as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 5

        let receiver = AudioOutputReceiver(handler: handler)

        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(
            receiver,
            type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "ainotetaker.system-audio.output", qos: .userInitiated)
        )

        try await stream.startCapture()

        self.stream = stream
        self.receiver = receiver
        self.isRunning = true

        Log.audio.info("SystemAudioCapture started")
    }

    public func stop() async throws {
        guard isRunning, let stream = stream else {
            throw AudioCaptureError.streamFailed(underlying: SystemAudioCaptureError.notRunning)
        }
        try await stream.stopCapture()
        self.stream = nil
        self.receiver = nil
        isRunning = false

        Log.audio.info("SystemAudioCapture stopped")
    }
}

private enum SystemAudioCaptureError: Error {
    case noDisplays
    case notRunning
}

/// Forwards SCStream audio sample buffers into a caller-supplied handler.
/// Lives at file scope because SCStreamOutput conformance must be on a class.
private final class AudioOutputReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let handler: AudioBufferHandler

    init(handler: @escaping AudioBufferHandler) { self.handler = handler }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let pcm = sampleBuffer.asPCMBuffer() else { return }
        handler(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.audio.error("SCStream stopped with error: \(error.localizedDescription, privacy: .public)")
    }
}
