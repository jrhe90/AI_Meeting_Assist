import Foundation
import SharedKit

/// Renders a `Meeting` to a self-contained Markdown document and writes it
/// to disk.
///
/// While the app remains sandboxed without user-Documents access, exports
/// land in `~/Library/Containers/com.ainotetaker.app/Data/Documents/AI Note Taker/`.
/// Once we add a `user-selected.read-write` entitlement + bookmark flow
/// the destination becomes the PLAN's `~/Documents/AI Note Taker/`.
public enum MarkdownExporter {
    public static var exportDirectory: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("AI Note Taker", isDirectory: true)
    }

    @MainActor
    @discardableResult
    public static func export(_ meeting: Meeting) -> URL? {
        let directory = exportDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("Failed to create export dir: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let url = directory.appendingPathComponent(filename(for: meeting))
        let body = render(meeting)
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            Log.storage.info("Exported markdown to \(url.path, privacy: .public)")
            return url
        } catch {
            Log.storage.error("Failed to write markdown: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @MainActor
    public static func render(_ meeting: Meeting) -> String {
        var lines: [String] = []
        lines.append("# \(meeting.title)")
        lines.append("")
        lines.append("- **Started:** \(formatted(meeting.startedAt))")
        if let ended = meeting.endedAt {
            lines.append("- **Ended:** \(formatted(ended))")
            let durationSeconds = Int(ended.timeIntervalSince(meeting.startedAt))
            lines.append("- **Duration:** \(durationSeconds / 60)m \(String(format: "%02d", durationSeconds % 60))s")
        }
        lines.append("- **Segments:** \(meeting.segments.count)")
        lines.append("")

        if let summary = meeting.summary {
            lines.append("## Summary")
            lines.append("")
            lines.append(summary.tldr)
            lines.append("")

            if !summary.decisions.isEmpty {
                lines.append("### Decisions")
                lines.append("")
                for decision in summary.decisions {
                    lines.append("- \(decision)")
                }
                lines.append("")
            }

            if !summary.actionItems.isEmpty {
                lines.append("### Action items")
                lines.append("")
                for item in summary.actionItems {
                    var line = "- \(item.detail)"
                    var attribs: [String] = []
                    if let assignee = item.assignee, !assignee.isEmpty { attribs.append("owner: \(assignee)") }
                    if let due = item.dueDate, !due.isEmpty { attribs.append("due: \(due)") }
                    if !attribs.isEmpty { line += " _(\(attribs.joined(separator: ", ")))_" }
                    lines.append(line)
                }
                lines.append("")
            }

            if !summary.topics.isEmpty {
                lines.append("### Topics")
                lines.append("")
                for topic in summary.topics {
                    lines.append("**\(topic.title)**")
                    for bullet in topic.bullets {
                        lines.append("- \(bullet)")
                    }
                    lines.append("")
                }
            }
        }

        lines.append("## Transcript")
        lines.append("")
        let sorted = meeting.segments.sorted { $0.start < $1.start }
        for segment in sorted {
            let tag = segment.side == .me ? "Me" : "Others"
            let total = Int(segment.start)
            let ts = String(format: "%02d:%02d", total / 60, total % 60)
            lines.append("**[\(ts) \(tag)]** \(segment.text)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func filename(for meeting: Meeting) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        let date = dateFmt.string(from: meeting.startedAt)
        let slug = slugify(meeting.title)
        return "\(date)-\(slug).md"
    }

    private static func slugify(_ string: String) -> String {
        let lowered = string.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var out = ""
        var lastWasDash = false
        for char in lowered {
            if allowed.contains(char) {
                out.append(char)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "meeting" : trimmed
    }

    private static func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
