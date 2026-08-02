import SwiftUI
import UniformTypeIdentifiers
import WriterblocksCore

extension UTType {
    static let writerblocksStory = UTType(exportedAs: "com.writerblocks.story")
}

/// A story, as a document you own.
///
/// `FileDocument` is what buys Open, Save, Save As, Duplicate, Rename, autosave,
/// Versions and iCloud Drive from the system rather than from code written here.
struct StoryDocument: FileDocument {

    /// `.json` is readable too, so a story exported from the web prototype opens
    /// without being renamed first.
    static var readableContentTypes: [UTType] { [.writerblocksStory, .json] }
    static var writableContentTypes: [UTType] { [.writerblocksStory] }

    var project: Project

    init(project: Project = Stories.createProject()) {
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        project = try StoryFile.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try StoryFile.encode(project))
    }
}
