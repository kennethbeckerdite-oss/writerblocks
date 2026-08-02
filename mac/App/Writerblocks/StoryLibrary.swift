import AppKit
import Foundation
import WriterblocksCore

/// One story as it appears on the home screen.
struct StoryCard: Identifiable, Equatable {
    let url: URL
    let title: String
    /// The logline if the story has one, else its first answered block.
    let subtitle: String
    let updatedAt: Date
    let stats: ProjectStats

    var id: URL { url }
}

/// Finding, creating and opening stories on disk.
enum StoryLibrary {

    /// Where a story goes when the writer has not said otherwise.
    ///
    /// Raising a save panel the instant someone has typed a logline would break
    /// exactly the flow the home screen exists to protect. Save As moves it
    /// anywhere later.
    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("writerblocks", isDirectory: true)
    }

    private static func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: - Listing

    static func stories() -> [StoryCard] {
        var urls = Set<URL>()

        if let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in contents where url.pathExtension == "writerblocks" {
                urls.insert(url.standardizedFileURL)
            }
        }

        // Stories saved elsewhere still belong on the home screen.
        for url in NSDocumentController.shared.recentDocumentURLs
        where url.pathExtension == "writerblocks" && FileManager.default.fileExists(atPath: url.path) {
            urls.insert(url.standardizedFileURL)
        }

        return urls
            .compactMap(card(for:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func card(for url: URL) -> StoryCard? {
        guard let data = try? Data(contentsOf: url),
              let project = try? StoryFile.decode(data)
        else { return nil }

        return StoryCard(
            url: url,
            title: project.title,
            subtitle: subtitle(of: project),
            updatedAt: Date(timeIntervalSince1970: project.updatedAt / 1000),
            stats: OutlineBuilder.stats(project)
        )
    }

    private static func subtitle(of project: Project) -> String {
        let answered = project.blocks
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.order < $1.order }

        if let logline = answered.first(where: { $0.questionId == "logline" }) {
            return logline.answer
        }
        return answered.first?.answer ?? "No blocks yet."
    }

    // MARK: - Creating

    /// Answering the logline *is* creating a story: the sentence becomes the
    /// first block and the deck moves straight on to the main character.
    static func create(logline: String) throws -> URL {
        try ensureFolder()

        var project = Stories.createProject()
        if let dealt = Deck.nextQuestion(project) {
            project = Stories.applyAnswer(project, dealt, logline)
        }
        project = Stories.renameProject(project, title: Stories.labelFromAnswer(logline))

        let url = try uniqueURL(named: Markdown.slugify(project.title))
        try StoryFile.encode(project).write(to: url, options: .atomic)
        return url
    }

    private static func uniqueURL(named slug: String) throws -> URL {
        let base = slug.isEmpty ? "untitled" : slug
        var candidate = folder.appendingPathComponent("\(base).writerblocks")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(n).writerblocks")
            n += 1
        }
        return candidate
    }

    // MARK: - Opening

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func duplicate(_ url: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        var project = try StoryFile.decode(data)
        project = duplicated(project)

        try ensureFolder()
        let copy = try uniqueURL(named: Markdown.slugify(project.title))
        try StoryFile.encode(project).write(to: copy, options: .atomic)
        return copy
    }

    /// A copy needs fresh ids throughout — blocks reference strands by id, so a
    /// shallow copy would leave two stories quietly entangled.
    private static func duplicated(_ project: Project) -> Project {
        var copy = project
        copy.id = UUID().uuidString
        copy.title = "\(project.title) copy"

        var strandIds: [String: String] = [:]
        copy.strands = project.strands.map { strand in
            var s = strand
            s.id = UUID().uuidString
            strandIds[strand.id] = s.id
            return s
        }

        var blockIds: [String: String] = [:]
        copy.blocks = project.blocks.compactMap { block in
            guard let newStrandId = strandIds[block.strandId] else { return nil }
            var b = block
            b.id = UUID().uuidString
            b.strandId = newStrandId
            blockIds[block.id] = b.id
            return b
        }

        // Skips are keyed by strand id, so they have to be remapped too.
        var skipped: [String: Int] = [:]
        for (key, at) in project.skipped {
            let parts = key.components(separatedBy: "::")
            guard parts.count == 2, let newStrandId = strandIds[parts[0]] else { continue }
            skipped[Deck.skipKey(newStrandId, parts[1])] = at
        }
        copy.skipped = skipped

        return copy
    }
}
