import Foundation
import Observation
import SwiftUI
import Transcription

/// App-wide user preferences backed by UserDefaults.
///
/// Language selection used to live here too, but is now fully automatic:
/// each meeting's first successful detection pins the language via
/// `LanguagePin` and all subsequent chunks reuse it. No knob, no setting.
@MainActor
@Observable
public final class Preferences {
    public static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let modelID = "whisperModelID"
    }

    public var selectedModel: WhisperModel {
        didSet {
            defaults.set(selectedModel.id, forKey: Keys.modelID)
        }
    }

    private init() {
        let storedID = UserDefaults.standard.string(forKey: Keys.modelID) ?? ""
        self.selectedModel = WhisperModelCatalog.model(withID: storedID) ?? WhisperModelCatalog.default
    }

    /// Filesystem URL where the active model lives (or would live, post-download).
    public var activeModelURL: URL {
        AppPaths.modelsDirectory.appendingPathComponent(selectedModel.filename)
    }
}
