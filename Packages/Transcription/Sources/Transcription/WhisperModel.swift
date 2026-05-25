import Foundation

/// Catalog entry for a downloadable whisper.cpp ggml model.
///
/// `expectedBytes` is the exact final file size on disk; the downloader uses
/// it to detect a previously-completed install without a HEAD request.
public struct WhisperModel: Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let summary: String
    public let filename: String
    public let sourceURL: URL
    public let expectedBytes: Int64
    public let isMultilingual: Bool

    public init(
        id: String,
        displayName: String,
        summary: String,
        filename: String,
        sourceURL: URL,
        expectedBytes: Int64,
        isMultilingual: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.filename = filename
        self.sourceURL = sourceURL
        self.expectedBytes = expectedBytes
        self.isMultilingual = isMultilingual
    }
}

public enum WhisperModelCatalog {
    public static let smallEnglish = WhisperModel(
        id: "small.en",
        displayName: "Small (English only)",
        summary: "~466 MB. Fastest. Best quality for English-only meetings.",
        filename: "ggml-small.en.bin",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
        expectedBytes: 487_601_967,
        isMultilingual: false
    )

    public static let smallMultilingual = WhisperModel(
        id: "small",
        displayName: "Small (multilingual)",
        summary: "~488 MB. Same speed as English-only. Handles 99 languages.",
        filename: "ggml-small.bin",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
        expectedBytes: 487_621_440,
        isMultilingual: true
    )

    public static let medium = WhisperModel(
        id: "medium",
        displayName: "Medium (multilingual)",
        summary: "~1.5 GB. ~3× slower than Small. Noticeably better on Chinese, Japanese, code-switching.",
        filename: "ggml-medium.bin",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
        expectedBytes: 1_533_763_059,
        isMultilingual: true
    )

    public static let large = WhisperModel(
        id: "large-v3",
        displayName: "Large v3 (multilingual)",
        summary: "~3.1 GB. Best quality. Slow — may take 1–2 min per 10s chunk on M-series.",
        filename: "ggml-large-v3.bin",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
        expectedBytes: 3_094_623_691,
        isMultilingual: true
    )

    public static let all: [WhisperModel] = [smallEnglish, smallMultilingual, medium, large]

    public static let `default`: WhisperModel = smallMultilingual

    public static func model(withID id: String) -> WhisperModel? {
        all.first { $0.id == id }
    }
}
