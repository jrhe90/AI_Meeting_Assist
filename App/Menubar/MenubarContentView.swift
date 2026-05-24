import SwiftUI

struct MenubarContentView: View {
    @Environment(\.openWindow) private var openWindow

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

#Preview {
    MenubarContentView()
}
