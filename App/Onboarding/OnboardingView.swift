import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel
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
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomePane()
        case .microphone: MicrophonePane(model: model)
        case .screenRecording: ScreenRecordingPane(model: model)
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
                Text("Welcome to AI Note Taker").font(.largeTitle).bold()
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

            Text("AI Note Taker needs to record your microphone so it can transcribe what you say during meetings.")

            statusRow(
                status: model.micStatus,
                deniedHint: "Open System Settings → Privacy & Security → Microphone and enable AI Note Taker."
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
                deniedHint: "Open System Settings → Privacy & Security → Screen & System Audio Recording and enable AI Note Taker."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DonePane: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable().frame(width: 56, height: 56)
                .foregroundStyle(.green)
            Text("You're all set").font(.largeTitle).bold()
            Text("AI Note Taker lives in your menu bar. Click the waveform icon to start a meeting.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
