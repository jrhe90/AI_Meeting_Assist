import Foundation
import SwiftData
import SharedKit

// Full SwiftData wiring (relationships, the @Model graph in §9 step 6) lands
// alongside the streaming pipeline. Keeping the @Model declarations minimal
// here so the package compiles before that work begins.

@Model
public final class Meeting {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(id: UUID = UUID(), title: String, startedAt: Date = .now, endedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
