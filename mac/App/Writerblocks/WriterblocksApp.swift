import SwiftUI
import WriterblocksCore

@main
struct WriterblocksApp: App {

    var body: some Scene {
        // A document app normally launches straight into an Open panel with no
        // home screen at all. This one deliberately does not: the whole premise
        // is that the app's front door is a question, so the launch window is
        // the logline, with past work underneath it.
        Window("Stories", id: WindowID.home) {
            HomeView()
        }
        .defaultSize(width: 1020, height: 720)

        // ⌘N here creates an untitled story, which opens on the logline
        // question anyway — the same first question the home screen asks.
        DocumentGroup(newDocument: StoryDocument()) { file in
            EditorView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export Markdown…") {
                    NotificationCenter.default.post(name: .exportMarkdown, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowList) {
                StoriesWindowButton()
            }
        }
    }
}

enum WindowID {
    static let home = "home"
}

/// Reopening the home window needs the environment action, which is only
/// available inside a view.
private struct StoriesWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Stories") { openWindow(id: WindowID.home) }
            .keyboardShortcut("0", modifiers: .command)
    }
}

extension Notification.Name {
    static let exportMarkdown = Notification.Name("writerblocks.exportMarkdown")
}
