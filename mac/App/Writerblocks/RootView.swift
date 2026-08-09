import AppKit
import SwiftUI
import WriterblocksCore

enum Route: Equatable {
    case home
    case story(URL)
}

/// Where the window currently is, and the only thing that moves it.
///
/// A singleton because the menu commands and the Finder open handler both need
/// to steer the window, and neither of them sits inside the view tree.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published private(set) var route: Route = .home
    @Published private(set) var store: StoryStore?
    @Published var error: String?
    /// Bumped to put the cursor back in the logline field when arriving home.
    @Published private(set) var focusLogline = 0

    private init() {}

    func open(_ url: URL) {
        do {
            store = try StoryStore(contentsOf: url)
            StoryLibrary.remember(url)
            route = .story(url)
            error = nil
        } catch {
            self.error = "Could not open that story: \(error.localizedDescription)"
        }
    }

    func goHome() {
        // Leaving the story is a natural place to be certain it is on disk.
        store?.saveNow()
        route = .home
    }

    /// Home, with the logline field focused — what ⌘N means in an app whose way
    /// of starting a story is to answer a question.
    func newStory() {
        goHome()
        focusLogline += 1
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.writerblocksStory, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
}

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        ZStack {
            if router.route == .home {
                HomeView(focusToken: router.focusLogline) { url in
                    AppRouter.shared.open(url)
                }
                .transition(.opacity)
            } else if let store = router.store {
                StoryView(store: store) {
                    AppRouter.shared.goHome()
                }
                // Double-clicking a second story in Finder goes straight from
                // one story to the next without passing through home, so
                // without this the editor's state — which tab, which question,
                // a half-typed sentence — would carry over into someone else's
                // story.
                .id(store.url)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: router.route)
        .frame(minWidth: 860, minHeight: 600)
        .alert(
            "Could not open that story",
            isPresented: Binding(
                get: { router.error != nil },
                set: { if !$0 { router.error = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.error ?? "")
        }
    }
}
