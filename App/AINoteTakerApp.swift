import SwiftUI

@main
struct AINoteTakerApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenubarContentView()
        } label: {
            // System image flips when recording (wired up at step 5).
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)

        Window("Library", id: WindowID.library) {
            LibraryView()
        }
        .defaultSize(width: 800, height: 520)
    }
}

enum WindowID {
    static let library = "library"
    static let meetingDetail = "meeting-detail"
}
