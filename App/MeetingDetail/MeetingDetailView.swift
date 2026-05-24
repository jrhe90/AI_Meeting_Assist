import Storage
import SwiftData
import SwiftUI

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                if let summary = meeting.summary {
                    summarySection(summary)
                } else {
                    pendingSummaryRow
                }
                Divider()
                transcriptSection
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 520)
        .navigationTitle(meeting.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).font(.title).bold()
            HStack(spacing: 12) {
                Text(startedString).foregroundStyle(.secondary)
                Text(durationString).foregroundStyle(.secondary)
                Text("\(meeting.segments.count) segments").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func summarySection(_ summary: StoredSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Summary", systemImage: "sparkles")
            Text(summary.tldr)
                .font(.body)
                .textSelection(.enabled)

            if !summary.decisions.isEmpty {
                sectionTitle("Decisions", systemImage: "checkmark.seal")
                ForEach(summary.decisions, id: \.self) { decision in
                    HStack(alignment: .firstTextBaseline) {
                        Text("•").foregroundStyle(.secondary)
                        Text(decision).textSelection(.enabled)
                    }
                }
            }

            if !summary.actionItems.isEmpty {
                sectionTitle("Action items", systemImage: "checklist")
                ForEach(summary.actionItems) { item in
                    ActionItemRow(item: item)
                }
            }

            if !summary.topics.isEmpty {
                sectionTitle("Topics", systemImage: "list.bullet.indent")
                ForEach(summary.topics) { topic in
                    TopicRow(topic: topic)
                }
            }
        }
    }

    private var pendingSummaryRow: some View {
        Label("No summary generated. Foundation Models may not be available on this build, or the meeting had no audible speech.",
              systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .font(.callout)
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Transcript", systemImage: "text.alignleft")
            ForEach(sortedSegments) { segment in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sideLabel(for: segment))
                            .font(.caption).bold()
                            .foregroundStyle(sideColor(for: segment))
                        Text(timestamp(segment.start))
                            .font(.caption2).foregroundStyle(.tertiary).monospaced()
                    }
                    .frame(width: 64, alignment: .leading)

                    Text(segment.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }

    private var sortedSegments: [StoredTranscriptSegment] {
        meeting.segments.sorted { $0.start < $1.start }
    }

    private var startedString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: meeting.startedAt)
    }

    private var durationString: String {
        guard let end = meeting.endedAt else { return "in progress" }
        let seconds = Int(end.timeIntervalSince(meeting.startedAt))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%dm %02ds", m, s)
    }

    private func sideLabel(for segment: StoredTranscriptSegment) -> String {
        segment.side == .me ? "Me" : "Others"
    }

    private func sideColor(for segment: StoredTranscriptSegment) -> Color {
        segment.side == .me ? .blue : .purple
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ActionItemRow: View {
    let item: StoredActionItem
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("•").foregroundStyle(.secondary)
                Text(item.detail).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                if let assignee = item.assignee, !assignee.isEmpty {
                    Label(assignee, systemImage: "person").font(.caption).foregroundStyle(.secondary)
                }
                if let due = item.dueDate, !due.isEmpty {
                    Label(due, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 12)
        }
    }
}

private struct TopicRow: View {
    let topic: StoredTopic
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title).font(.subheadline).bold()
            ForEach(topic.bullets, id: \.self) { bullet in
                HStack(alignment: .firstTextBaseline) {
                    Text("◦").foregroundStyle(.secondary)
                    Text(bullet).textSelection(.enabled)
                }
                .padding(.leading, 12)
            }
        }
    }
}
