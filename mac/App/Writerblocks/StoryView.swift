import SwiftUI
import WriterblocksCore

enum EditorTab: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case board = "Board"
    case web = "Web"
    case outline = "Outline"

    var id: String { rawValue }
}

/// "Ask me about these two" — a one-shot, cleared as soon as it is answered.
struct PairFocus: Equatable {
    let subject: String
    let about: String
}

struct StoryView: View {
    @ObservedObject var store: StoryStore
    let onHome: () -> Void

    @State private var tab: EditorTab = .ask
    @State private var pairFocus: PairFocus?
    @State private var renaming = false
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    /// The web only earns a tab once there are people in it and enough written
    /// down to be worth looking at.
    private var tabs: [EditorTab] {
        Webs.isOpen(store.project) ? EditorTab.allCases : EditorTab.allCases.filter { $0 != .web }
    }

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
                AskView(project: $store.project, pairFocus: $pairFocus)
            case .board:
                BoardView(project: $store.project)
            case .web:
                WebView(project: $store.project) { subject, about in
                    pairFocus = PairFocus(subject: subject, about: about)
                    tab = .ask
                }
            case .outline:
                OutlineDocumentView(project: store.project, onExport: store.exportMarkdown)
            }
        }
        .onChange(of: tabs) { _, available in
            // The last character was deleted while the web was open.
            if !available.contains(tab) { tab = .ask }
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

            ToolbarItem(placement: .navigation) {
                titleField
            }

            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(tabs) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: tabs.count > 3 ? 300 : 240)
            }

            ToolbarItem(placement: .primaryAction) {
                Text(savedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The story's name, click to change it.
    ///
    /// Not the real title bar: making that editable means handing the window a
    /// document proxy, whose menu offers Rename and Move To. Those rename the
    /// *file*, and the store writes to the path it was opened with — so a
    /// system rename would quietly resurrect the old file on the next save.
    @ViewBuilder
    private var titleField: some View {
        if renaming {
            TextField("Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.headline)
                .frame(width: 200)
                .focused($titleFocused)
                .onSubmit(commitRename)
                // Clicking away commits too. Throwing the edit out because the
                // writer looked at something else is the kind of small
                // betrayal that stops people trusting a text field.
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitRename() }
                }
        } else {
            Text(store.project.title)
                .font(.headline)
                .lineLimit(1)
                .help("\(store.project.title) — click to rename")
                .onTapGesture {
                    draftTitle = store.project.title
                    renaming = true
                    titleFocused = true
                }
        }
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        store.project = Stories.retitle(store.project, title: draftTitle)
    }

    private var savedLabel: String {
        if store.saveError != nil { return "Not saved" }
        if store.isSaving { return "Saving…" }
        guard let lastSaved = store.lastSaved else { return "" }
        return "Saved \(lastSaved.formatted(date: .omitted, time: .shortened))"
    }
}
