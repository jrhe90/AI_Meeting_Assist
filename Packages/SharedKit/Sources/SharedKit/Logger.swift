import Foundation
import os

public enum Log {
    public static let subsystem = "com.ainotetaker"

    public static let app       = Logger(subsystem: subsystem, category: "app")
    public static let audio     = Logger(subsystem: subsystem, category: "audio")
    public static let whisper   = Logger(subsystem: subsystem, category: "whisper")
    public static let summary   = Logger(subsystem: subsystem, category: "summary")
    public static let storage   = Logger(subsystem: subsystem, category: "storage")
}
