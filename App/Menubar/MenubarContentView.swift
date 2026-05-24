import AppKit
import AudioCapture
import SharedKit
import Storage
import SwiftData
import SwiftUI
import Transcription

struct MenubarContentView: View {
    let session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @State private var spike = SpikeController()
    @State private var transcribe = TranscribeController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FirstLaunchPresenter()

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("AI Note Taker").font(.headline)
            }

            meetingButton

            Divider()

            Button {
                openWindow(id: WindowID.library)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open library", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: WindowID.onboarding)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Show welcome…", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            #if DEBUG
            Divider()
            SpikeDebugRow(spike: spike)
            TranscribeDebugRow(transcribe: transcribe)
            #endif

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240)
    }

    @ViewBuilder
    private var meetingButton: some View {
        switch session.state {
        case .idle, .error:
            Button {
                openWindow(id: WindowID.liveMeeting)
                NSApp.activate(ignoringOtherApps: true)
                session.start()
            } label: {
                Label("Start meeting", systemImage: "record.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
        case .starting:
            Button {} label: {
                Label("Starting…", systemImage: "hourglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .running:
            Button(role: .destructive) {
                session.stop()
            } label: {
                Label("Stop meeting", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
        case .stopping:
            Button {} label: {
                Label("Stopping…", systemImage: "hourglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .summarizing:
            Button {} label: {
                Label("Summarizing…", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }
}

#if DEBUG

@MainActor
@Observable
final class SpikeController {
    enum State: Equatable {
        case idle
        case starting
        case running(mode: SpikeRunner.Mode)
        case stopping
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.starting, .starting), (.stopping, .stopping): return true
            case (.running(let a), .running(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var lastDirectory: URL?
    private let runner = SpikeRunner()

    func start(mode: SpikeRunner.Mode) {
        state = .starting
        Task {
            do {
                let dir = try await runner.start(mode: mode)
                await MainActor.run {
                    self.lastDirectory = dir
                    self.state = .running(mode: mode)
                }
            } catch {
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
        }
    }

    func stop() {
        state = .stopping
        Task {
            do {
                let output = try await runner.stop()
                await MainActor.run {
                    self.lastDirectory = output.directory
                    self.state = .idle
                    var urls: [URL] = [output.system.url]
                    if let mic = output.mic { urls.append(mic.url) }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            } catch {
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
        }
    }

    func reset() {
        state = .idle
    }
}

@MainActor
@Observable
final class TranscribeController {
    enum State: Equatable {
        case idle
        case running
        case done(segments: Int, preview: String)
        case error(String)
    }

    private(set) var state: State = .idle

    /// Where step 11 will eventually drop the auto-downloaded model. For now
    /// the user supplies this path manually via the curl command in the README.
    private var modelURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("AINoteTaker/models/ggml-small.en.bin")
    }

    func transcribeLastSpike() {
        state = .running
        Task {
            do {
                guard let wav = try Self.findMostRecentSystemWAV() else {
                    await MainActor.run {
                        self.state = .error("No spike WAV found — run a capture spike first.")
                    }
                    return
                }
                let engine = WhisperEngine(modelURL: modelURL)
                let segments = try await engine.transcribe(wavURL: wav, side: .others)
                let preview = segments.prefix(3).map(\.text).joined(separator: " ")
                let fullText = segments.map(\.text).joined(separator: " ")
                Log.whisper.info("Transcript: \(fullText, privacy: .public)")
                await MainActor.run {
                    self.state = .done(segments: segments.count, preview: preview)
                }
            } catch {
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
        }
    }

    func reset() { state = .idle }

    private static func findMostRecentSystemWAV() throws -> URL? {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let spikeDir = support.appendingPathComponent("AINoteTaker/spike", isDirectory: true)

        guard FileManager.default.fileExists(atPath: spikeDir.path) else { return nil }

        let runs = try FileManager.default
            .contentsOfDirectory(at: spikeDir, includingPropertiesForKeys: [.contentModificationDateKey])
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }

        for run in runs {
            let candidate = run.appendingPathComponent("system.wav")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

private struct TranscribeDebugRow: View {
    let transcribe: TranscribeController

    var body: some View {
        switch transcribe.state {
        case .idle:
            Button { transcribe.transcribeLastSpike() } label: {
                Label("Transcribe last spike", systemImage: "text.quote")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        case .running:
            Label("Transcribing…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .done(let count, let preview):
            VStack(alignment: .leading, spacing: 4) {
                Label("\(count) segments", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if !preview.isEmpty {
                    Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Button("Dismiss") { transcribe.reset() }.buttonStyle(.borderless)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Transcribe failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Reset") { transcribe.reset() }.buttonStyle(.borderless)
            }
        }
    }
}

private struct SpikeDebugRow: View {
    let spike: SpikeController

    var body: some View {
        switch spike.state {
        case .idle:
            VStack(alignment: .leading, spacing: 6) {
                Button { spike.start(mode: .dual) } label: {
                    Label("Run spike (mic + system)", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button { spike.start(mode: .systemOnly) } label: {
                    Label("Run spike (system only)", systemImage: "speaker.wave.2")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        case .starting:
            Label("Starting…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .running(let mode):
            Button { spike.stop() } label: {
                Label(mode == .dual ? "Stop dual spike & reveal" : "Stop system spike & reveal",
                      systemImage: "stop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        case .stopping:
            Label("Stopping…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Spike failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Reset") { spike.reset() }.buttonStyle(.borderless)
            }
        }
    }
}

#endif

#Preview {
    let schema = Schema(StorageSchema.models)
    let container = try! ModelContainer(for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    return MenubarContentView(session: MeetingSession(
        modelURL: AppPaths.whisperModelURL,
        modelContext: ModelContext(container)
    ))
}
