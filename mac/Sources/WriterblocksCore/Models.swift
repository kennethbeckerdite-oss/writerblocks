import Foundation

/// A strand is a subject the questions circle around: the premise itself, a
/// person, a place, or the run of scenes. Blocks hang off a strand.
public enum StrandType: String, Codable, Sendable, CaseIterable {
    case premise
    case character
    case setting
    case scene
}

/// Where a block lands when the blocks are assembled into an outline.
///
/// Always derived from the strand a block currently sits on (see
/// `sectionForStrandType`), never stored — so moving a card on the board moves
/// it in the outline too, with nothing left to fall out of sync.
public enum OutlineSection: String, Codable, Sendable, CaseIterable {
    case premise
    case character
    case setting
    case structure
}

public struct Strand: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: StrandType
    /// "Marla", "The diner", "Scenes" — usually seeded from the answer that spawned it.
    public var label: String
    public var order: Int
    public var createdAt: Double

    public init(id: String, type: StrandType, label: String, order: Int, createdAt: Double) {
        self.id = id
        self.type = type
        self.label = label
        self.order = order
        self.createdAt = createdAt
    }
}

public struct Block: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var strandId: String
    /// nil for a free-form block the writer added themselves.
    public var questionId: String?
    /// The question exactly as it was asked, with the subject already substituted.
    public var prompt: String
    /// One sentence. Empty means "not sure yet" — an open thread, not a failure.
    public var answer: String
    /// Chronological position in the story, for scene blocks. nil = unplaced.
    public var beat: Int?
    /// Position within the strand.
    public var order: Int
    public var createdAt: Double

    public init(
        id: String,
        strandId: String,
        questionId: String?,
        prompt: String,
        answer: String,
        beat: Int?,
        order: Int,
        createdAt: Double
    ) {
        self.id = id
        self.strandId = strandId
        self.questionId = questionId
        self.prompt = prompt
        self.answer = answer
        self.beat = beat
        self.order = order
        self.createdAt = createdAt
    }
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var schemaVersion: Int
    public var strands: [Strand]
    public var blocks: [Block]
    /// Questions the writer skipped: `strandId::questionId` mapped to the block
    /// count at the moment of the skip. The skip lapses once a few more blocks
    /// are down, so "skip for now" really does mean for now.
    public var skipped: [String: Int]
    public var createdAt: Double
    public var updatedAt: Double

    public init(
        id: String,
        title: String,
        schemaVersion: Int,
        strands: [Strand],
        blocks: [Block],
        skipped: [String: Int],
        createdAt: Double,
        updatedAt: Double
    ) {
        self.id = id
        self.title = title
        self.schemaVersion = schemaVersion
        self.strands = strands
        self.blocks = blocks
        self.skipped = skipped
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct QuestionTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var strandType: StrandType
    /// May contain {subject}, replaced with the strand's label when asked. Keep
    /// it to the question itself — this text is stored on the block and read
    /// back in the outline, so encouragement belongs in `hint`.
    public var text: String
    /// Shown under the question while answering. Never stored on the block.
    public var hint: String?
    /// Lower is asked earlier.
    public var priority: Int
    /// Answering this creates a new strand of the given type, named from the answer.
    public var spawns: StrandType?
    /// Answering this names the project. A blank answer leaves the title alone.
    public var titles: Bool?
    /// Question ids that only become askable once this one is answered.
    public var unlocks: [String]?
    /// Scene questions only: where this sits in story chronology (0 = open, 100 = close).
    public var beat: Int?
    /// Can be asked more than once for the same strand.
    public var repeatable: Bool?

    public var isRepeatable: Bool { repeatable ?? false }
}

/// What the deck hands back when it has something to ask.
public struct DealtQuestion: Equatable, Sendable {
    public let template: QuestionTemplate
    public let strand: Strand
    /// `template.text` with {subject} resolved.
    public let text: String

    public init(template: QuestionTemplate, strand: Strand, text: String) {
        self.template = template
        self.strand = strand
        self.text = text
    }
}

/* ---- Outline shapes (built from blocks, never stored) ---- */

public struct OutlineGroup: Equatable, Identifiable, Sendable {
    /// The strand this group came from, or a synthetic grouping like "unplaced".
    public let id: String
    public let heading: String?
    public let blocks: [Block]
}

public struct OutlineSectionView: Equatable, Identifiable, Sendable {
    public let section: OutlineSection
    public let heading: String
    public let groups: [OutlineGroup]

    public var id: String { section.rawValue }
}

public typealias Outline = [OutlineSectionView]
