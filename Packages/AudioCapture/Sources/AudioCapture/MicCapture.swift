import AVFoundation
import Foundation
import SharedKit

/// A handler that receives raw PCM buffers as they arrive from the capture
/// engine. The closure runs on a real-time audio thread; do as little work
/// as possible inside it (copy/append to a queue, then return).
public typealias AudioBufferHandler = @Sendable (AVAudioPCMBuffer) -> Void

/// Captures the microphone via AVAudioEngine and delivers PCM buffers to a
/// caller-supplied handler.
///
/// AVAudioEngine's input node uses the OS-selected default input device. The
/// hardware format (sample rate, channel count) is whatever the device reports;
/// the handler sees buffers in that format and is responsible for any
/// conversion it needs.
public actor MicCapture {
    private let engine = AVAudioEngine()
    private var isRunning = false

    public init() {}

    public func start(handler: @escaping AudioBufferHandler) async throws {
        guard !isRunning else { return }

        // Check for an input device *before* touching the engine. Calling
        // engine.prepare() on a Mac with no default input throws an
        // NSException ("inputNode != nullptr || outputNode != nullptr") that
        // crashes the process; this lookup, in contrast, only reports a
        // zero-sample-rate format.
        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            throw micGranted ? AudioCaptureError.noInputDeviceAvailable
                             : AudioCaptureError.microphonePermissionDenied
        }

        Log.audio.info("Mic hardware format: \(hwFormat.sampleRate, privacy: .public) Hz, \(hwFormat.channelCount, privacy: .public) ch")

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
            handler(buffer)
        }

        do {
            try engine.start()  // start() prepares the graph internally.
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.streamFailed(underlying: error)
        }
    }

    public func stop() async throws {
        guard isRunning else {
            throw AudioCaptureError.streamFailed(underlying: MicCaptureError.notRunning)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

private enum MicCaptureError: Error { case notRunning }
