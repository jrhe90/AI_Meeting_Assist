import AppKit
import SwiftUI

@main
struct AINoteTakerApp: App {
    @Environment(\.openWindow) private var openWindow

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

        Window("Welcome to AI Note Taker", id: WindowID.onboarding) {
            OnboardingHost()
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

enum WindowID {
    static let library = "library"
    static let meetingDetail = "meeting-detail"
    static let onboarding = "onboarding"
}

/// Hosts `OnboardingView` and owns the view model. Self-dismisses when finished
/// and triggers a one-shot present on first launch via `.task`.
private struct OnboardingHost: View {
    @State private var model = OnboardingViewModel()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        OnboardingView(model: model) {
            dismissWindow(id: WindowID.onboarding)
        }
    }
}

/// Opens the onboarding window on first launch. Mounted invisibly in the
/// MenuBarExtra so it runs once when the app comes up.
struct FirstLaunchPresenter: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didPresent = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                guard !didPresent, !OnboardingFlag.isCompleted else { return }
                didPresent = true
                openWindow(id: WindowID.onboarding)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
