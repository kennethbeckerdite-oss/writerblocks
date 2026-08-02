import SwiftUI
import UniformTypeIdentifiers
import WriterblocksCore

enum EditorTab: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case board = "Board"
    case outline = "Outline"

    var id: String { rawValue }
}

struct EditorView: View {
    @Binding var document: StoryDocument
    @State private var tab: EditorTab = .ask
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .ask:
                AskView(project: $document.project)
            case .board:
                BoardView(project: $document.project)
            case .outline:
                OutlineDocumentView(project: document.project)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(EditorTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        .navigationTitle(document.project.title)
        .onReceive(NotificationCenter.default.publisher(for: .exportMarkdown)) { _ in
            exporting = true
        }
        .fileExporter(
            isPresented: $exporting,
            document: MarkdownFile(text: Markdown.render(document.project)),
            contentType: .plainText,
            defaultFilename: Markdown.slugify(document.project.title)
        ) { _ in }
    }
}

/// Markdown export rides on `fileExporter`, which wants a `FileDocument`.
struct MarkdownFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
