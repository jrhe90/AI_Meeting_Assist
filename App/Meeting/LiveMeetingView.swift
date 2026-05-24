import SwiftUI
import Transcription

struct LiveMeetingView: View {
    @Bindable var session: MeetingSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var header: some View {
        HStack {
            statusBadge
            Spacer()
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(elapsedString).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.state {
        case .idle:
            Label("Idle", systemImage: "circle").foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .running:
            Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red)
        case .stopping:
            Label("Stopping…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if session.segments.isEmpty {
                    ContentUnavailableView {
                        Label("Listening…", systemImage: "waveform")
                    } description: {
                        Text("Transcribed segments appear here every ~10 seconds.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(session.segments, id: \.id) { segment in
                        SegmentRow(segment: segment)
                    }
                }
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            switch session.state {
            case .idle, .error:
                Button {
                    session.start()
                } label: {
                    Label("Start meeting", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .starting, .stopping:
                Button("Working…") {}.disabled(true).buttonStyle(.borderedProminent)
            case .running:
                Button(role: .destructive) {
                    session.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var elapsedString: String {
        guard let started = session.startedAt else { return "00:00" }
        let elapsed = Int(Date().timeIntervalSince(started))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}

private struct SegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption).bold()
                    .foregroundStyle(color)
                Text(timestamp).font(.caption2).foregroundStyle(.tertiary).monospaced()
            }
            .frame(width: 64, alignment: .leading)

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var label: String {
        switch segment.side {
        case .me: return "Me"
        case .others: return "Others"
        }
    }

    private var color: Color {
        switch segment.side {
        case .me: return .blue
        case .others: return .purple
        }
    }

    private var timestamp: String {
        let total = Int(segment.start)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
