import AppKit
import SharedKit
import Storage
import SwiftData
import SwiftUI

@main
struct AINoteTakerApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var session: MeetingSession
    @State private var preferences = Preferences.shared

    private let container: ModelContainer

    init() {
        let schema = Schema(StorageSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let resolvedContainer: ModelContainer
        do {
            resolvedContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Log.storage.fault("Failed to create ModelContainer: \(error.localizedDescription, privacy: .public)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.container = resolvedContainer
        let context = ModelContext(resolvedContainer)
        _session = State(initialValue: MeetingSession(
            preferences: Preferences.shared,
            modelContext: context
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenubarContentView(session: session)
                .modelContainer(container)
        } label: {
            // Icon flips to a filled record dot while a meeting is running.
            Image(systemName: session.state == .running ? "record.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.window)

        Window("Library", id: WindowID.library) {
            LibraryView()
                .modelContainer(container)
        }
        .defaultSize(width: 800, height: 520)

        Window("Welcome to AI Note Taker", id: WindowID.onboarding) {
            OnboardingHost()
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        Window("Live Meeting", id: WindowID.liveMeeting) {
            LiveMeetingView(session: session)
                .modelContainer(container)
        }
        .defaultSize(width: 640, height: 480)

        Settings {
            SettingsView(preferences: preferences)
        }
    }
}

enum WindowID {
    static let library = "library"
    static let meetingDetail = "meeting-detail"
    static let onboarding = "onboarding"
    static let liveMeeting = "live-meeting"
}

/// Canonical filesystem paths the app reads/writes. The currently active
/// model URL lives on `Preferences` since the user can switch between
/// whisper models at runtime.
enum AppPaths {
    static var modelsDirectory: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("AINoteTaker/models", isDirectory: true)
    }
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
