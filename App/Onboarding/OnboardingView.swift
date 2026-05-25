import AppKit
import SwiftUI
import Transcription

struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel
    @State private var downloader = WhisperModelDownloader(
        model: Preferences.shared.selectedModel,
        destinationURL: Preferences.shared.activeModelURL
    )
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)

            Divider()

            HStack {
                stepIndicator
                Spacer()
                primaryButton
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onChange(of: model.step) { _, newStep in
            if newStep == .modelDownload && downloader.status == .idle {
                downloader.start()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomePane()
        case .microphone: MicrophonePane(model: model)
        case .screenRecording: ScreenRecordingPane(model: model)
        case .modelDownload: ModelDownloadPane(downloader: downloader)
        case .done: DonePane()
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= model.step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.step {
        case .welcome:
            Button("Get started") { model.advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

        case .microphone:
            if model.micStatus == .notDetermined {
                Button {
                    Task { await model.requestMicrophone() }
                } label: {
                    Text(model.isRequesting ? "Requesting…" : "Allow microphone")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRequesting)
            } else {
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

        case .screenRecording:
            if model.screenStatus == .notDetermined {
                Button {
                    model.requestScreenRecording()
                } label: {
                    Text(model.isRequesting ? "Requesting…" : "Allow screen recording")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRequesting)
            } else {
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

        case .modelDownload:
            switch downloader.status {
            case .completed:
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Retry") { downloader.retry() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .idle, .checking, .downloading:
                Button("Working…") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }

        case .done:
            Button("Finish") {
                model.finish()
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Panes

private struct WelcomePane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .resizable().frame(width: 40, height: 40)
                    .foregroundStyle(.tint)
                Text("Welcome to Nox").font(.largeTitle).bold()
            }
            Text("Private, on-device meeting notes for Mac.")
                .font(.title3).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Label("Audio is processed entirely on this Mac.", systemImage: "lock.shield")
            Label("Raw recordings are discarded after transcription.", systemImage: "trash.slash")
            Label("No telemetry. No analytics. No network calls.", systemImage: "wifi.slash")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MicrophonePane: View {
    let model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Microphone access", systemImage: "mic.fill")
                .font(.title).bold()

            Text("Nox needs to record your microphone so it can transcribe what you say during meetings.")

            statusRow(
                status: model.micStatus,
                deniedHint: "Open System Settings → Privacy & Security → Microphone and enable Nox."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScreenRecordingPane: View {
    let model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Screen recording access", systemImage: "rectangle.on.rectangle")
                .font(.title).bold()

            Text("To capture system audio (the other person's voice in a video call), macOS requires screen recording permission. No video is ever recorded — only the audio output.")

            statusRow(
                status: model.screenStatus,
                deniedHint: "Open System Settings → Privacy & Security → Screen & System Audio Recording and enable Nox."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelDownloadPane: View {
    let downloader: WhisperModelDownloader

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Download the speech model", systemImage: "square.and.arrow.down")
                .font(.title).bold()

            Text("Nox uses a whisper.cpp model to transcribe meetings on-device. The default is the multilingual small model (\(Self.formatMB(downloader.model.expectedBytes))). You can switch models later in Settings.")

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch downloader.status {
        case .idle, .checking:
            Label("Checking for existing download…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: downloader.fractionComplete) {
                    Text(progressLabel).font(.callout).foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                Text("Downloads can be paused — closing the wizard will resume next time you open it.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        case .completed:
            Label("Model ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.callout).foregroundStyle(.secondary)
                Text("Check your network connection and click Retry below.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var progressLabel: String {
        let received = Self.formatMB(downloader.bytesReceived)
        let total = downloader.totalBytes > 0
            ? Self.formatMB(downloader.totalBytes)
            : Self.formatMB(downloader.model.expectedBytes)
        let pct = Int((downloader.fractionComplete * 100).rounded())
        return "\(received) of \(total) (\(pct)%)"
    }

    private static func formatMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

private struct DonePane: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable().frame(width: 56, height: 56)
                .foregroundStyle(.green)
            Text("You're all set").font(.largeTitle).bold()
            Text("Nox lives in your menu bar. Click the waveform icon to start a meeting.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
@ViewBuilder
private func statusRow(status: PermissionStatus, deniedHint: String) -> some View {
    switch status {
    case .notDetermined:
        Label("Not requested yet", systemImage: "questionmark.circle")
            .foregroundStyle(.secondary)
    case .granted:
        Label("Permission granted", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    case .denied:
        VStack(alignment: .leading, spacing: 8) {
            Label("Permission denied", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(deniedHint)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    OnboardingView(model: OnboardingViewModel(), onFinish: {})
}
