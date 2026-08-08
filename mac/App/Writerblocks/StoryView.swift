import SwiftUI
import WriterblocksCore

enum EditorTab: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case board = "Board"
    case outline = "Outline"

    var id: String { rawValue }
}

struct StoryView: View {
    @ObservedObject var store: StoryStore
    let onHome: () -> Void

    @State private var tab: EditorTab = .ask

    var body: some View {
        VStack(spacing: 0) {
            // Saving is hand-rolled now, so a failure has to be impossible to
            // miss — losing writes silently is the worst thing this app could do.
            if let saveError = store.saveError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("This story could not be saved: \(saveError)")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Export Markdown…") { store.exportMarkdown() }
                }
                .font(.callout)
                .padding(10)
                .background(Color.orange.opacity(0.22))
            }

            switch tab {
            case .ask:
                AskView(project: $store.project)
            case .board:
                BoardView(project: $store.project)
            case .outline:
                OutlineDocumentView(project: store.project, onExport: store.exportMarkdown)
            }
        }
        .navigationTitle(store.project.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    onHome()
                } label: {
                    Label("Stories", systemImage: "square.grid.2x2")
                }
                .help("Back to your stories")
            }

            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(EditorTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            ToolbarItem(placement: .primaryAction) {
                Text(savedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var savedLabel: String {
        if store.saveError != nil { return "Not saved" }
        if store.isSaving { return "Saving…" }
        guard let lastSaved = store.lastSaved else { return "" }
        return "Saved \(lastSaved.formatted(date: .omitted, time: .shortened))"
    }
}
