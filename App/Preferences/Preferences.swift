import Foundation
import Observation
import SwiftUI
import Transcription

/// User-facing language options for whisper transcription. `auto` lets
/// whisper detect per-chunk — best for mixed-language meetings but a bit
/// slower; specific languages constrain decoding for higher quality.
public struct WhisperLanguage: Hashable, Identifiable, Sendable {
    public let code: String           // whisper's ISO-style code; empty == auto
    public let displayName: String

    public var id: String { code }
    public var isAuto: Bool { code.isEmpty }

    public static let auto      = WhisperLanguage(code: "",    displayName: "Auto-detect")
    public static let english   = WhisperLanguage(code: "en",  displayName: "English")
    public static let chinese   = WhisperLanguage(code: "zh",  displayName: "Chinese (Mandarin)")
    public static let japanese  = WhisperLanguage(code: "ja",  displayName: "Japanese")
    public static let korean    = WhisperLanguage(code: "ko",  displayName: "Korean")
    public static let spanish   = WhisperLanguage(code: "es",  displayName: "Spanish")
    public static let french    = WhisperLanguage(code: "fr",  displayName: "French")
    public static let german    = WhisperLanguage(code: "de",  displayName: "German")
    public static let portuguese = WhisperLanguage(code: "pt", displayName: "Portuguese")
    public static let russian   = WhisperLanguage(code: "ru",  displayName: "Russian")

    public static let all: [WhisperLanguage] = [
        .auto, .english, .chinese, .japanese, .korean, .spanish,
        .french, .german, .portuguese, .russian
    ]

    public static func byCode(_ code: String) -> WhisperLanguage {
        all.first { $0.code == code } ?? .auto
    }
}

/// App-wide user preferences backed by UserDefaults.
@MainActor
@Observable
public final class Preferences {
    public static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let modelID = "whisperModelID"
        static let languageCode = "whisperLanguageCode"
    }

    public var selectedModel: WhisperModel {
        didSet {
            defaults.set(selectedModel.id, forKey: Keys.modelID)
        }
    }

    public var selectedLanguage: WhisperLanguage {
        didSet {
            defaults.set(selectedLanguage.code, forKey: Keys.languageCode)
        }
    }

    private init() {
        let storedID = UserDefaults.standard.string(forKey: Keys.modelID) ?? ""
        self.selectedModel = WhisperModelCatalog.model(withID: storedID) ?? WhisperModelCatalog.default

        let storedCode = UserDefaults.standard.string(forKey: Keys.languageCode) ?? ""
        self.selectedLanguage = WhisperLanguage.byCode(storedCode)
    }

    /// Filesystem URL where the active model lives (or would live, post-download).
    public var activeModelURL: URL {
        AppPaths.modelsDirectory.appendingPathComponent(selectedModel.filename)
    }
}
