import AVFoundation
import Foundation
import SharedKit

/// Captures the microphone via AVAudioEngine and writes a WAV file.
///
/// AVAudioEngine's input node uses the OS-selected default input device. The
/// hardware format (sample rate, channel count) is whatever the device reports;
/// we let AVAudioFile convert into our canonical 48 kHz / mono / Int16 WAV.
public actor MicCapture {
    private let engine = AVAudioEngine()
    private var writer: WAVFileWriter?
    private var isRunning = false

    public init() {}

    public func start(writingTo url: URL) async throws {
        guard !isRunning else { return }

        let writer = WAVFileWriter(url: url)
        self.writer = writer

        engine.prepare()
        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            // A 0 Hz format means Core Audio has no usable default input device
            // for this process — either no hardware is attached (AirPods unpaired,
            // mic unplugged, built-in disabled) or TCC denied access.
            self.writer = nil
            let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            throw micGranted ? AudioCaptureError.noInputDeviceAvailable
                             : AudioCaptureError.microphonePermissionDenied
        }

        Log.audio.info("Mic hardware format: \(hwFormat.sampleRate, privacy: .public) Hz, \(hwFormat.channelCount, privacy: .public) ch")

        // The tap closure is @Sendable; capture the writer (which is its own
        // Sendable class with internal locking) instead of `self` to avoid the
        // actor-isolation hop on every audio buffer.
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
            do {
                try writer.write(buffer)
            } catch {
                Log.audio.error("Mic write failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            self.writer = nil
            throw AudioCaptureError.streamFailed(underlying: error)
        }
    }

    public func stop() async throws -> CaptureResult {
        guard isRunning, let writer = writer else {
            throw AudioCaptureError.streamFailed(underlying: MicCaptureError.notRunning)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        writer.close()
        self.writer = nil

        return CaptureResult(
            url: writer.url,
            sampleCount: writer.sampleCount,
            sampleRate: writer.actualSampleRate,
            channelCount: writer.actualChannelCount
        )
    }
}

private enum MicCaptureError: Error { case notRunning }
