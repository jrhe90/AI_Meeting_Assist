import AppKit
import AudioCapture
import SwiftUI

struct MenubarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var spike = SpikeController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FirstLaunchPresenter()

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("AI Note Taker").font(.headline)
            }

            Button {
                // TODO(step 5): start dual-stream capture + streaming transcription.
            } label: {
                Label("Start meeting", systemImage: "record.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)

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
    MenubarContentView()
}
