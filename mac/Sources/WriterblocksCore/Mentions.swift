import Foundation

/// Someone or somewhere the writer can name in a sentence.
public struct MentionSubject: Equatable, Identifiable, Sendable {
    /// nil for a subject that does not exist yet.
    public let strandId: String?
    public let type: StrandType
    /// What the menu shows — the whole label, however it was answered.
    public let label: String
    /// What goes into the sentence. Shorter than `label` when the character was
    /// named with a whole answer rather than a name.
    public let writes: String
    /// False when nothing in this label can be recognised again, so writing it
    /// will not connect anything.
    public let isMatchable: Bool

    public var id: String { strandId ?? "new::\(type.rawValue)" }
    public var isNew: Bool { strandId == nil }

    public init(strandId: String?, type: StrandType, label: String, writes: String, isMatchable: Bool) {
        self.strandId = strandId
        self.type = type
        self.label = label
        self.writes = writes
        self.isMatchable = isMatchable
    }
}

public struct MentionGroup: Equatable, Identifiable, Sendable {
    /// nil for the rows that make something new — they need no heading.
    public let heading: String?
    public let subjects: [MentionSubject]

    public var id: String { heading ?? "new" }
}

/// Naming a person or a place from inside a sentence.
///
/// All of it is here rather than in the view because none of the view can be
/// tested, and because the rules below are the whole feature — the drawing is
/// the easy half.
public enum Mentions {

    /// Longest run of text that could still be someone's name.
    static let maxToken = 40
    static let maxWords = 4

    /// Characters a name is allowed to contain. Everything else — a full stop,
    /// a comma, a question mark — means the writer has moved on, and is how the
    /// menu closes when a sentence runs past it.
    private static func isNameCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == " " || c == "-" || c == "'" || c == "’"
    }

    /// The name being typed after a `/`, or nil if there isn't one.
    ///
    /// Only ever found at the end of the draft: a `TextField` will not say where
    /// the caret is, so a `/` typed into the middle of an existing sentence does
    /// nothing at all. A silent no-op is the right failure — it is never a wrong
    /// action, only an absent one.
    public static func activeToken(in draft: String) -> String? {
        // The *last* slash, not the first unclosed one. This is what stops a
        // stray slash earlier in the sentence from holding the menu open for
        // ever: a later slash, or none, settles the question by itself.
        guard let slash = draft.lastIndex(of: "/") else { return nil }

        // Only after a space, or at the very beginning. "and/or", "24/7" and
        // "http://x" are not someone's name. This also makes the rule agree
        // with the matcher by construction rather than by luck — Webs.mentions
        // wants a word boundary to the left, and whitespace-or-start is exactly
        // that boundary, so whatever is dropped in lands where it will be
        // recognised again.
        if slash != draft.startIndex {
            let before = draft[draft.index(before: slash)]
            guard before.isWhitespace else { return nil }
        }

        let token = String(draft[draft.index(after: slash)...])
        guard token.allSatisfy(isNameCharacter) else { return nil }
        guard token.count <= maxToken else { return nil }
        guard token.split(whereSeparator: { $0.isWhitespace }).count <= maxWords else { return nil }
        return token
    }

    // MARK: - Who there is to name

    /// People and places, filtered by what has been typed so far.
    ///
    /// Premise and Scenes are strands too, but they are not subjects anyone
    /// writes about by name, so they are never offered.
    public static func candidates(_ project: Project, token: String) -> [MentionGroup] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var groups: [MentionGroup] = []

        // Making something new needs a name to give it. Offering it on an empty
        // token would produce a character called "Untitled", which the matcher
        // throws out as a stopword — a character that can never be connected to
        // anything is the worst thing this menu could make.
        if !trimmed.isEmpty {
            groups.append(
                MentionGroup(
                    heading: nil,
                    subjects: [
                        newSubject(.character, named: trimmed),
                        newSubject(.setting, named: trimmed)
                    ]
                )
            )
        }

        for (type, heading) in [(StrandType.character, "Characters"), (.setting, "Places")] {
            let found = project.strands
                .filter { $0.type == type && Mentions.matches($0.label, trimmed) }
                .sorted { $0.order < $1.order }
                .map(subject(for:))
            if !found.isEmpty {
                groups.append(MentionGroup(heading: heading, subjects: found))
            }
        }

        return groups
    }

    /// Deliberately prefix-only, on the label or on any word inside it, rather
    /// than anything fuzzier: a menu that keeps matching once the writer has
    /// moved on to ordinary prose is a menu that never gets out of the way.
    static func matches(_ label: String, _ token: String) -> Bool {
        guard !token.isEmpty else { return true }
        let needle = token.lowercased()
        let lowered = label.lowercased()
        if lowered.hasPrefix(needle) { return true }
        return lowered
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.hasPrefix(needle) }
    }

    static func subject(for strand: Strand) -> MentionSubject {
        let writable = Webs.matchable(for: strand.label)
        return MentionSubject(
            strandId: strand.id,
            type: strand.type,
            label: strand.label,
            // With nothing recognisable in the label there is nothing better to
            // offer than the label itself. It will read oddly and connect
            // nothing, and the menu says so rather than failing quietly.
            writes: writable ?? strand.label,
            isMatchable: writable != nil
        )
    }

    private static func newSubject(_ type: StrandType, named name: String) -> MentionSubject {
        MentionSubject(
            strandId: nil,
            type: type,
            label: name,
            writes: name,
            isMatchable: Webs.matchable(for: name) != nil
        )
    }

    // MARK: - Writing it in

    /// The draft with the half-typed name replaced by the real one.
    ///
    /// The trailing space is load-bearing, not tidiness: the matcher needs a
    /// word boundary on the right, so without it the next keystroke would glue
    /// onto the name and the connection would quietly never be made.
    ///
    /// Spelling is left exactly as the subject has it. Both sides are lowercased
    /// before matching, so case never decides whether a line is drawn, and
    /// rewriting someone's prose for no gain is not ours to do.
    public static func insert(_ subject: MentionSubject, into draft: String) -> String {
        guard let slash = draft.lastIndex(of: "/"), activeToken(in: draft) != nil else {
            return draft
        }
        return draft[draft.startIndex..<slash] + subject.writes + " "
    }
}
