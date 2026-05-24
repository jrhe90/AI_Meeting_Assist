import Foundation
import SharedKit

/// Drives the dual-stream audio capture spike from §9 step 3.
///
/// Records mic and system audio concurrently into the same timestamped
/// directory, then reports the resulting file URLs and sample counts so a
/// human (or test) can sanity-check duration and audibility.
public actor SpikeRunner {
    public enum Mode: Sendable {
        case dual
        case systemOnly
    }

    public struct Output: Sendable {
        public let directory: URL
        public let mic: CaptureResult?
        public let system: CaptureResult
    }

    private let mic = MicCapture()
    private let system = SystemAudioCapture()
    private var directory: URL?
    private var startedAt: Date?
    private var mode: Mode = .dual

    public init() {}

    public static func defaultOutputDirectory() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("AINoteTaker/spike", isDirectory: true)
    }

    public func start(mode: Mode = .dual) async throws -> URL {
        let stamp = Self.timestamp(Date())
        let dir = Self.defaultOutputDirectory().appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let systemURL = dir.appendingPathComponent("system.wav")

        Log.audio.info("Spike starting in \(dir.path, privacy: .public) mode=\(String(describing: mode), privacy: .public)")

        if mode == .dual {
            let micURL = dir.appendingPathComponent("mic.wav")
            try await mic.start(writingTo: micURL)
        }

        do {
            try await system.start(writingTo: systemURL)
        } catch {
            if mode == .dual { _ = try? await mic.stop() }
            throw error
        }

        self.directory = dir
        self.startedAt = Date()
        self.mode = mode
        return dir
    }

    public func stop() async throws -> Output {
        guard let dir = directory, let started = startedAt else {
            throw AudioCaptureError.streamFailed(underlying: SpikeError.notStarted)
        }

        let currentMode = mode

        // Stop both (when applicable) even if one throws so we never leak a stream.
        let systemResultTask: Task<CaptureResult, Error> = Task { try await self.system.stop() }
        let micResultTask: Task<CaptureResult, Error>? = (currentMode == .dual)
            ? Task { try await self.mic.stop() }
            : nil

        let systemResult = try await systemResultTask.value
        let micResult = try await micResultTask?.value

        let wallDuration = Date().timeIntervalSince(started)
        Self.logSmokeReport(wall: wallDuration, mic: micResult, system: systemResult)

        directory = nil
        startedAt = nil
        return Output(directory: dir, mic: micResult, system: systemResult)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func logSmokeReport(wall: TimeInterval, mic: CaptureResult?, system: CaptureResult) {
        let systemExpected = Int64(wall * system.sampleRate)
        let systemDrift = system.sampleCount - systemExpected
        if let mic {
            let micExpected = Int64(wall * mic.sampleRate)
            let micDrift = mic.sampleCount - micExpected
            Log.audio.info("""
                Spike report — wall=\(String(format: "%.2f", wall), privacy: .public)s
                mic: \(mic.sampleCount, privacy: .public) samples (\(String(format: "%.2f", mic.duration), privacy: .public)s, drift \(micDrift, privacy: .public))
                system: \(system.sampleCount, privacy: .public) samples (\(String(format: "%.2f", system.duration), privacy: .public)s, drift \(systemDrift, privacy: .public))
                """)
        } else {
            Log.audio.info("""
                Spike report — wall=\(String(format: "%.2f", wall), privacy: .public)s (system only)
                system: \(system.sampleCount, privacy: .public) samples (\(String(format: "%.2f", system.duration), privacy: .public)s, drift \(systemDrift, privacy: .public))
                """)
        }
    }
}

private enum SpikeError: Error { case notStarted }
