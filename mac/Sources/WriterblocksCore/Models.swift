import Foundation

/// A strand is a subject the questions circle around: the premise itself, a
/// person, a place, or the run of scenes. Blocks hang off a strand.
public enum StrandType: String, Codable, Sendable, CaseIterable {
    case premise
    case character
    case setting
    case scene
}

/// The two scales of place. A setting is somewhere the story happens and
/// somewhere a character can be *from*; a location is a spot inside one.
///
/// The distinction earns its keep in the deck: "were they born in Oregon?" is
/// worth asking and "were they born in the 7-11?" is not.
public enum PlaceTier: String, Codable, Sendable, CaseIterable {
    case setting
    case location
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
    /// The setting this one sits inside — the 7-11 in Oregon, the kitchen in
    /// the house. nil for everything else, including a setting itself.
    ///
    /// Only ever set on a `.setting` strand, and only ever pointing at a
    /// `.setting` with no parent of its own: places nest exactly two deep. See
    /// `Stories.parentIsUsable`.
    public var parentStrandId: String?

    public init(
        id: String,
        type: StrandType,
        label: String,
        order: Int,
        createdAt: Double,
        parentStrandId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.order = order
        self.createdAt = createdAt
        self.parentStrandId = parentStrandId
    }

    /// Which scale of place this is, or nil if it is not a place at all.
    ///
    /// nil rather than a default matters: if a character came back as
    /// `.setting` here, a tier put on a character question by mistake would
    /// quietly work, and a deck that behaves correctly by accident is harder to
    /// find a fault in than one that plainly does not.
    public var placeTier: PlaceTier? {
        guard type == .setting else { return nil }
        return parentStrandId == nil ? .setting : .location
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
    /// The other character this block is about, for a question asked about two
    /// people at once. nil for every ordinary block.
    ///
    /// The block still lives on one strand and still takes its outline section
    /// from that strand; this only records who else it concerns. The names are
    /// already substituted into `prompt`, so nothing downstream has to read it.
    public var aboutStrandId: String?

    public init(
        id: String,
        strandId: String,
        questionId: String?,
        prompt: String,
        answer: String,
        beat: Int?,
        order: Int,
        createdAt: Double,
        aboutStrandId: String? = nil
    ) {
        self.id = id
        self.strandId = strandId
        self.questionId = questionId
        self.prompt = prompt
        self.answer = answer
        self.beat = beat
        self.order = order
        self.createdAt = createdAt
        self.aboutStrandId = aboutStrandId
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
    /// Asked about two characters at once. The text carries {other} as well as
    /// {subject}, and it is only ever asked about a pair the story has
    /// connected.
    public var pairs: Bool?
    /// Which scale of place this is worth asking about. Absent means both.
    /// Only meaningful on a `setting` question.
    public var tier: PlaceTier?

    public var isRepeatable: Bool { repeatable ?? false }
    public var isPair: Bool { pairs ?? false }
}

/// What the deck hands back when it has something to ask.
public struct DealtQuestion: Equatable, Sendable {
    public let template: QuestionTemplate
    public let strand: Strand
    /// `template.text` with {subject} — and {other}, for a pair question —
    /// resolved.
    public let text: String
    /// The second character, for a question asked about two people at once.
    public let about: Strand?

    public init(template: QuestionTemplate, strand: Strand, text: String, about: Strand? = nil) {
        self.template = template
        self.strand = strand
        self.text = text
        self.about = about
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
