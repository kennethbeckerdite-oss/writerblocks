import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WriterblocksCore

extension UTType {
    static let writerblocksStory = UTType(exportedAs: "com.writerblocks.story")
}

/// The open story, and everything that used to come free from `DocumentGroup`.
///
/// Leaving `DocumentGroup` behind is what makes a single window with a crossfade
/// possible, but it means saving is now ours to get right. The prototype's one
/// real bug was swallowing write failures, so a failed save is surfaced here
/// rather than discarded.
@MainActor
final class StoryStore: ObservableObject {

    let url: URL

    @Published var project: Project {
        didSet { scheduleSave() }
    }

    @Published private(set) var isSaving = false
    @Published private(set) var lastSaved: Date?
    @Published private(set) var saveError: String?

    /// Long enough that a burst of typing collapses into one write, short enough
    /// that quitting a second after a sentence still catches it.
    private static let debounce: Duration = .milliseconds(600)

    private var saveTask: Task<Void, Never>?

    init(url: URL, project: Project) {
        self.url = url
        self.project = project
    }

    convenience init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(url: url, project: try StoryFile.decode(data))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Force a write now — leaving for the dashboard, quitting, or ⌘S. Anything
    /// pending is cancelled first so the same state is not written twice.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func write() {
        isSaving = true
        defer { isSaving = false }

        do {
            try StoryFile.encode(project).write(to: url, options: .atomic)
            lastSaved = Date()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Export

    func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(Markdown.slugify(project.title)).md"
        panel.title = "Export Markdown"

        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try Data(Markdown.render(project).utf8).write(to: target, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
