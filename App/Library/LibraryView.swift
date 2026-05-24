import Storage
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @Environment(\.modelContext) private var modelContext

    @State private var selection: Meeting?
    @State private var searchText: String = ""
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var meetingPendingDelete: Meeting?

    enum SortOrder: String, CaseIterable, Identifiable {
        case newestFirst, oldestFirst, titleAZ
        var id: String { rawValue }
        var label: String {
            switch self {
            case .newestFirst: return "Newest first"
            case .oldestFirst: return "Oldest first"
            case .titleAZ: return "Title A–Z"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selection {
                MeetingDetailView(meeting: selection)
            } else {
                ContentUnavailableView("Select a meeting",
                                        systemImage: "doc.text",
                                        description: Text("Choose a meeting on the left to see its summary and transcript."))
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: Binding(
                get: { meetingPendingDelete != nil },
                set: { if !$0 { meetingPendingDelete = nil } }
            ),
            presenting: meetingPendingDelete
        ) { meeting in
            Button("Delete", role: .destructive) {
                delete(meeting)
            }
            Button("Cancel", role: .cancel) {}
        } message: { meeting in
            Text("\"\(meeting.title)\" and its transcript will be removed. The exported Markdown file is also deleted.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            list
        }
        .frame(minWidth: 320)
        .navigationTitle("Library")
    }

    private var controls: some View {
        VStack(spacing: 8) {
            TextField("Search title or transcript", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        if filteredAndSorted.isEmpty {
            ContentUnavailableView {
                Label(meetings.isEmpty ? "No meetings yet" : "No matches",
                      systemImage: meetings.isEmpty ? "mic.slash" : "magnifyingglass")
            } description: {
                Text(meetings.isEmpty
                    ? "Click the menubar icon and Start meeting to record one."
                    : "Try a different search term or sort order.")
            }
            .padding()
        } else {
            List(filteredAndSorted, selection: $selection) { meeting in
                MeetingRow(meeting: meeting)
                    .tag(meeting)
                    .contextMenu {
                        Button(role: .destructive) {
                            meetingPendingDelete = meeting
                        } label: {
                            Label("Delete…", systemImage: "trash")
                        }
                    }
            }
        }
    }

    // MARK: - Data

    private var filteredAndSorted: [Meeting] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [Meeting]
        if trimmed.isEmpty {
            filtered = meetings
        } else {
            filtered = meetings.filter { meeting in
                if meeting.title.lowercased().contains(trimmed) { return true }
                return meeting.segments.contains { $0.text.lowercased().contains(trimmed) }
            }
        }

        switch sortOrder {
        case .newestFirst: return filtered.sorted { $0.startedAt > $1.startedAt }
        case .oldestFirst: return filtered.sorted { $0.startedAt < $1.startedAt }
        case .titleAZ: return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    // MARK: - Actions

    private func delete(_ meeting: Meeting) {
        if selection == meeting { selection = nil }
        MarkdownExporter.deleteExport(for: meeting)
        modelContext.delete(meeting)
        try? modelContext.save()
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title).font(.headline)
                HStack(spacing: 12) {
                    Text(startedString).font(.caption).foregroundStyle(.secondary)
                    Text(durationString).font(.caption).foregroundStyle(.secondary)
                    Text("\(meeting.segments.count) segments").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if meeting.endedAt == nil {
                Label("Recording", systemImage: "record.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
    }

    private var startedString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
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
}

#Preview {
    LibraryView()
}
