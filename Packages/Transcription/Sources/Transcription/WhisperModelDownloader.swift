import Foundation
import Observation
import SharedKit

/// Downloads the whisper.cpp ggml model file with progress reporting and
/// resume support.
///
/// Uses `URLSessionDownloadDelegate` (rather than `URLSession.bytes(for:)`),
/// which yields chunked progress callbacks and is much faster on large files.
/// Resume across in-app cancels uses Apple's `resumeData` API. Resume across
/// app relaunches is best-effort — see `start()`.
@MainActor
@Observable
public final class WhisperModelDownloader: NSObject {
    public enum Status: Sendable, Equatable {
        case idle
        case checking
        case downloading
        case completed
        case failed(String)
    }

    public static let defaultSourceURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
    )!

    /// Expected final size of `ggml-small.en.bin`. Used to detect a previously
    /// completed install without a HEAD request.
    public static let expectedBytes: Int64 = 487_601_967

    public private(set) var status: Status = .idle
    public private(set) var bytesReceived: Int64 = 0
    public private(set) var totalBytes: Int64 = 0

    public var fractionComplete: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }

    public let sourceURL: URL
    public let destinationURL: URL

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    /// Apple's opaque resume token. Stored so we can survive in-app cancels.
    /// (Not persisted to disk — a relaunched app starts fresh.)
    private var resumeData: Data?

    public init(
        sourceURL: URL = WhisperModelDownloader.defaultSourceURL,
        destinationURL: URL
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        super.init()
    }

    // MARK: - Public surface

    public func isAlreadyInstalled() -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
        guard let size = attrs?[.size] as? NSNumber else { return false }
        return size.int64Value >= Self.expectedBytes
    }

    public func start() {
        guard task == nil else { return }

        status = .checking
        if isAlreadyInstalled() {
            bytesReceived = Self.expectedBytes
            totalBytes = Self.expectedBytes
            status = .completed
            Log.whisper.info("Whisper model already present at \(self.destinationURL.path, privacy: .public)")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            status = .failed("Failed to create model directory: \(error.localizedDescription)")
            return
        }

        let config = URLSessionConfiguration.default
        // Reasonable timeouts — long enough that a slow connection isn't dropped
        // mid-flight, short enough to surface server-side stalls.
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task: URLSessionDownloadTask
        if let resumeData {
            Log.whisper.info("Resuming whisper model download from \(resumeData.count, privacy: .public) bytes of resume data")
            task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            task = session.downloadTask(with: sourceURL)
        }
        self.task = task
        status = .downloading
        task.resume()
    }

    public func retry() {
        cancel()
        resumeData = nil
        bytesReceived = 0
        totalBytes = 0
        status = .idle
        start()
    }

    public func cancel() {
        task?.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                self?.resumeData = data
            }
        })
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if status == .downloading { status = .idle }
    }
}

// MARK: - URLSessionDownloadDelegate

extension WhisperModelDownloader: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bytesReceived = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite > 0
                ? totalBytesExpectedToWrite
                : Self.expectedBytes
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The delegate gives us a temp file that will be deleted as soon as
        // this method returns; move it synchronously.
        let dest = destinationURL
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: location, to: dest)
        } catch {
            Task { @MainActor [weak self] in
                self?.status = .failed("Failed to move downloaded model: \(error.localizedDescription)")
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bytesReceived = Self.expectedBytes
            self.totalBytes = Self.expectedBytes
            self.status = .completed
            self.task = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            Log.whisper.info("Whisper model downloaded to \(self.destinationURL.path, privacy: .public)")
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        let stashed = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resumeData = stashed
            self.task = nil
            // CancellationError surfaces as NSURLErrorCancelled; don't display it.
            if nsError.code == NSURLErrorCancelled {
                if self.status == .downloading { self.status = .idle }
            } else {
                self.status = .failed(error.localizedDescription)
                Log.whisper.error("Whisper download failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
