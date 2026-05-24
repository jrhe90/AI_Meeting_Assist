import Foundation

public struct CaptureResult: Sendable, Hashable {
    public let url: URL
    public let sampleCount: Int64
    public let sampleRate: Double
    public let channelCount: Int

    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(sampleCount) / sampleRate
    }

    public init(url: URL, sampleCount: Int64, sampleRate: Double, channelCount: Int) {
        self.url = url
        self.sampleCount = sampleCount
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}
