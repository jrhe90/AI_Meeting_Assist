import Storage
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]

    var body: some View {
        Group {
            if meetings.isEmpty {
                ContentUnavailableView {
                    Label("No meetings yet", systemImage: "mic.slash")
                } description: {
                    Text("Click the menubar icon and Start meeting to record one.")
                }
            } else {
                List(meetings) { meeting in
                    MeetingRow(meeting: meeting)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("Library")
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
