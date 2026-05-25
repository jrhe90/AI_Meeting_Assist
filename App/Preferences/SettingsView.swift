import SwiftUI
import Transcription

struct SettingsView: View {
    @Bindable var preferences: Preferences
    @State private var manager = ModelManager()

    var body: some View {
        TabView {
            transcriptionTab
                .tabItem { Label("Transcription", systemImage: "waveform") }
        }
        .frame(width: 560, height: 460)
        .onAppear {
            manager.refresh(for: preferences.selectedModel, destination: preferences.activeModelURL)
        }
        .onChange(of: preferences.selectedModel) { _, newModel in
            manager.refresh(for: newModel, destination: preferences.activeModelURL)
        }
    }

    private var transcriptionTab: some View {
        Form {
            Section("Model") {
                Picker("Whisper model", selection: $preferences.selectedModel) {
                    ForEach(WhisperModelCatalog.all) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                Text(preferences.selectedModel.summary)
                    .font(.caption).foregroundStyle(.secondary)

                modelStatusRow
            }

            Section("Language") {
                Picker("Default language", selection: $preferences.selectedLanguage) {
                    ForEach(WhisperLanguage.all) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .disabled(!preferences.selectedModel.isMultilingual && preferences.selectedLanguage != .english && preferences.selectedLanguage != .auto)

                if !preferences.selectedModel.isMultilingual {
                    Text("This model only supports English. Switch to a multilingual model to use other languages.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if preferences.selectedLanguage.isAuto {
                    Text("Whisper detects the language per chunk. Best for mixed-language meetings; specific languages give tighter quality.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        switch manager.status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notInstalled:
            HStack {
                Label("Not downloaded", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download (\(formatMB(preferences.selectedModel.expectedBytes)))") {
                    manager.startDownload(for: preferences.selectedModel,
                                          destination: preferences.activeModelURL)
                }
                .buttonStyle(.borderedProminent)
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: manager.fractionComplete) {
                    Text("Downloading \(formatMB(manager.bytesReceived)) of \(formatMB(manager.totalBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel") { manager.cancel() }
                    .buttonStyle(.borderless)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Retry") {
                    manager.startDownload(for: preferences.selectedModel,
                                          destination: preferences.activeModelURL)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func formatMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

/// Drives downloads for the model picker. Holds a single active downloader at
/// a time and rebuilds it when the selected model changes.
@MainActor
@Observable
final class ModelManager {
    enum Status: Equatable {
        case installed
        case notInstalled
        case downloading
        case failed(String)
    }

    private(set) var status: Status = .notInstalled
    private(set) var bytesReceived: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    var fractionComplete: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }

    private var downloader: WhisperModelDownloader?
    private var observation: Task<Void, Never>?

    func refresh(for model: WhisperModel, destination: URL) {
        observation?.cancel()
        let dl = WhisperModelDownloader(model: model, destinationURL: destination)
        downloader = dl
        if dl.isAlreadyInstalled() {
            status = .installed
            bytesReceived = model.expectedBytes
            totalBytes = model.expectedBytes
        } else {
            status = .notInstalled
            bytesReceived = 0
            totalBytes = 0
        }
    }

    func startDownload(for model: WhisperModel, destination: URL) {
        let dl = downloader ?? WhisperModelDownloader(model: model, destinationURL: destination)
        downloader = dl
        status = .downloading
        bytesReceived = 0
        totalBytes = model.expectedBytes
        dl.start()
        observation?.cancel()
        observation = Task { [weak self, dl] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.bytesReceived = dl.bytesReceived
                self.totalBytes = max(self.totalBytes, dl.totalBytes)
                switch dl.status {
                case .completed:
                    self.status = .installed
                    return
                case .failed(let message):
                    self.status = .failed(message)
                    return
                case .downloading, .checking, .idle:
                    continue
                }
            }
        }
    }

    func cancel() {
        downloader?.cancel()
        observation?.cancel()
        observation = nil
        status = .notInstalled
        bytesReceived = 0
        totalBytes = 0
    }
}
