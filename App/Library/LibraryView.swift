import SwiftUI

struct LibraryView: View {
    var body: some View {
        // Real list view lands at step 10; this is the skeleton placeholder.
        ContentUnavailableView {
            Label("No meetings yet", systemImage: "mic.slash")
        } description: {
            Text("Recorded meetings will appear here once you've finished your first session.")
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("Library")
    }
}

#Preview {
    LibraryView()
}
