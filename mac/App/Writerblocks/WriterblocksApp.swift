import AppKit
import SwiftUI
import WriterblocksCore

@main
struct WriterblocksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // One window. The dashboard and a story are two states of it, not two
        // windows — which is what lets one crossfade into the other.
        Window("writerblocks", id: "main") {
            RootView()
        }
        .defaultSize(width: 1020, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Story") { AppRouter.shared.newStory() }
                    .keyboardShortcut("n")

                Button("Open…") { AppRouter.shared.openPanel() }
                    .keyboardShortcut("o")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { AppRouter.shared.store?.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(AppRouter.shared.store == nil)

                Button("Export Markdown…") { AppRouter.shared.store?.exportMarkdown() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(AppRouter.shared.store == nil)
            }

            CommandGroup(after: .toolbar) {
                Button("Stories") { AppRouter.shared.goHome() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

/// `DocumentGroup` used to handle double-clicking a story in Finder and saving
/// on quit. Neither has any visible UI to remind us it is gone, so both are
/// picked up here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppRouter.shared.open(url)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRouter.shared.store?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
