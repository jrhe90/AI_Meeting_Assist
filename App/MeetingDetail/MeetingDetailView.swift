import Storage
import SwiftData
import SwiftUI

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                if let summary = meeting.summary {
                    SummarySection(summary: summary, save: save)
                } else {
                    pendingSummaryRow
                }
                Divider()
                TranscriptSection(meeting: meeting, save: save)
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 520)
        .navigationTitle(meeting.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    save()
                    if let url = MarkdownExporter.export(meeting) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Export Markdown", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onDisappear {
            save()
            MarkdownExporter.export(meeting)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $meeting.title)
                .textFieldStyle(.plain)
                .font(.title)
                .bold()
                .onSubmit(save)

            HStack(spacing: 12) {
                Text(startedString).foregroundStyle(.secondary)
                Text(durationString).foregroundStyle(.secondary)
                Text("\(meeting.segments.count) segments").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var pendingSummaryRow: some View {
        Label("No summary generated. Foundation Models may not be available on this build, or the meeting had no audible speech.",
              systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .font(.callout)
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

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - Summary section

private struct SummarySection: View {
    @Bindable var summary: StoredSummary
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Summary", systemImage: "sparkles")
            TextEditor(text: $summary.tldr)
                .font(.body)
                .frame(minHeight: 60)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: summary.tldr) { _, _ in save() }

            DecisionsBlock(summary: summary, save: save)
            ActionItemsBlock(summary: summary, save: save)
            TopicsBlock(summary: summary, save: save)
        }
    }

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage).font(.headline)
    }
}

private struct DecisionsBlock: View {
    @Bindable var summary: StoredSummary
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Decisions", systemImage: "checkmark.seal").font(.headline)
                Spacer()
                Button {
                    summary.decisions.append("")
                    save()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if summary.decisions.isEmpty {
                Text("None").foregroundStyle(.tertiary).font(.callout)
            } else {
                ForEach(summary.decisions.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline) {
                        Text("•").foregroundStyle(.secondary)
                        TextField("Decision", text: $summary.decisions[index])
                            .textFieldStyle(.plain)
                            .onSubmit(save)
                        Button {
                            summary.decisions.remove(at: index)
                            save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ActionItemsBlock: View {
    @Bindable var summary: StoredSummary
    let save: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Action items", systemImage: "checklist").font(.headline)
                Spacer()
                Button {
                    let item = StoredActionItem(detail: "")
                    item.summary = summary
                    modelContext.insert(item)
                    save()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if summary.actionItems.isEmpty {
                Text("None").foregroundStyle(.tertiary).font(.callout)
            } else {
                ForEach(summary.actionItems) { item in
                    ActionItemRow(item: item, save: save) {
                        modelContext.delete(item)
                        save()
                    }
                }
            }
        }
    }
}

private struct ActionItemRow: View {
    @Bindable var item: StoredActionItem
    let save: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("•").foregroundStyle(.secondary)
                TextField("Action", text: $item.detail)
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label {
                    TextField("Assignee", text: Binding(
                        get: { item.assignee ?? "" },
                        set: { item.assignee = $0.isEmpty ? nil : $0; save() }
                    ))
                    .textFieldStyle(.plain)
                } icon: { Image(systemName: "person") }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label {
                    TextField("Due", text: Binding(
                        get: { item.dueDate ?? "" },
                        set: { item.dueDate = $0.isEmpty ? nil : $0; save() }
                    ))
                    .textFieldStyle(.plain)
                } icon: { Image(systemName: "calendar") }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
        }
    }
}

private struct TopicsBlock: View {
    @Bindable var summary: StoredSummary
    let save: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Topics", systemImage: "list.bullet.indent").font(.headline)
                Spacer()
                Button {
                    let topic = StoredTopic(title: "New topic")
                    topic.summary = summary
                    modelContext.insert(topic)
                    save()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if summary.topics.isEmpty {
                Text("None").foregroundStyle(.tertiary).font(.callout)
            } else {
                ForEach(summary.topics) { topic in
                    TopicRow(topic: topic, save: save) {
                        modelContext.delete(topic)
                        save()
                    }
                }
            }
        }
    }
}

private struct TopicRow: View {
    @Bindable var topic: StoredTopic
    let save: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Topic title", text: $topic.title)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .bold()
                    .onSubmit(save)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            ForEach(topic.bullets.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline) {
                    Text("◦").foregroundStyle(.secondary)
                    TextField("Bullet", text: $topic.bullets[index])
                        .textFieldStyle(.plain)
                        .onSubmit(save)
                    Button {
                        topic.bullets.remove(at: index)
                        save()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
            }

            Button {
                topic.bullets.append("")
                save()
            } label: {
                Label("Add bullet", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 12)
        }
    }
}

// MARK: - Transcript section

private struct TranscriptSection: View {
    let meeting: Meeting
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcript", systemImage: "text.alignleft").font(.headline)
            ForEach(sortedSegments) { segment in
                TranscriptRow(segment: segment, save: save)
            }
        }
    }

    private var sortedSegments: [StoredTranscriptSegment] {
        meeting.segments.sorted { $0.start < $1.start }
    }
}

private struct TranscriptRow: View {
    @Bindable var segment: StoredTranscriptSegment
    let save: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.side == .me ? "Me" : "Others")
                    .font(.caption).bold()
                    .foregroundStyle(segment.side == .me ? Color.blue : Color.purple)
                Text(timestamp(segment.start))
                    .font(.caption2).foregroundStyle(.tertiary).monospaced()
            }
            .frame(width: 64, alignment: .leading)

            TextField("Transcript", text: $segment.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { save() }
                }
        }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
