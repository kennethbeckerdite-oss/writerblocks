import Foundation

/// One connection between two characters.
///
/// Undirected: `a` and `b` are ordered by strand id so a pair has exactly one
/// edge however it was found.
public struct WebEdge: Equatable, Identifiable, Sendable {
    public let a: String
    public let b: String
    /// Times one of them turned up in an answer written about the other.
    public let mentions: Int
    /// Blocks asked about the two of them together, in either direction.
    public let pairBlocks: Int

    public var id: String { "\(a)::\(b)" }

    /// A pair the writer has actually written something about, rather than one
    /// the tool noticed a name in.
    public var isAnswered: Bool { pairBlocks > 0 }

    public func other(than strandId: String) -> String? {
        strandId == a ? b : (strandId == b ? a : nil)
    }
}

/// Who is connected to whom.
///
/// Nothing here is stored. Edges are recomputed from the blocks every time,
/// exactly as an outline section is recomputed from the strand a block sits on
/// — so renaming a character re-forms the web for free, and there is no second
/// copy of the truth to drift out of date.
public enum Webs {

    /// A web needs two people to be a web.
    public static let minCharacters = 2

    /// And enough written down to be worth looking at.
    ///
    /// Measured in blocks rather than in characters on purpose: two names typed
    /// into the premise in the first minute are not yet a cast, and a graph of
    /// two dots and one line is a discouraging thing to be shown. By the time
    /// this many sentences exist there is something to see.
    public static let minBlocks = 15

    public static func isOpen(_ project: Project) -> Bool {
        project.strands.filter { $0.type == .character }.count >= minCharacters
            && project.blocks.count >= minBlocks
    }

    // MARK: - Matching

    /// Labels that would match half the story. A character called "The Man"
    /// would otherwise be mentioned by every sentence containing the word "man".
    private static let stopwords: Set<String> = [
        "he", "she", "him", "her", "they", "them", "the", "a", "an", "his", "hers",
        "man", "woman", "boy", "girl", "kid", "child", "mother", "father", "mom",
        "dad", "brother", "sister", "son", "daughter", "wife", "husband",
        "friend", "someone", "everyone", "nobody", "narrator", "untitled"
    ]

    /// A label long enough that it is a description rather than a name gets
    /// matched on its first word instead, and only if that word looks like one.
    private static let longLabel = 20

    /// ASCII alphanumerics, the hyphen, and every byte of a multi-byte
    /// character.
    ///
    /// Treating bytes >= 0x80 as part of a word is what stops "Ana" matching
    /// inside "Anaïs": every UTF-8 continuation byte is >= 0x80, so the
    /// boundary comes out right without decoding anything. An apostrophe is
    /// deliberately *not* a word byte, so "Marla's" matches Marla.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39)   // 0-9
            || (byte >= 0x61 && byte <= 0x7A) // a-z (haystacks are lowercased)
            || (byte >= 0x41 && byte <= 0x5A) // A-Z
            || byte == 0x2D                   // -
            || byte >= 0x80
    }

    /// The part of a label that can actually be hunted for in a sentence, in
    /// its original spelling — or nil if none of it can be.
    ///
    /// Split out from `needle` because it is useful on its own: a menu that
    /// offers a character to write about wants to *show* the whole label,
    /// "Marla Vance, who runs the yard…", and *insert* the part that will be
    /// recognised again, "Marla". Inserting the whole clipped answer would be
    /// bad prose and would not read back any better.
    public static func matchable(for label: String) -> String? {
        var trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last, last == "…" || ".,;:".contains(last) {
            trimmed.removeLast()
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)

        // A clipped answer — "A retired dockworker who never lef…" — will never
        // appear inside another sentence verbatim, so searching for the whole
        // thing is dead code for exactly the labels this is worried about. Use
        // the first word, and only when it reads as a name: capitalised, and not
        // a word the story is going to be full of anyway.
        if trimmed.count > longLabel {
            guard let first = trimmed.split(whereSeparator: { $0.isWhitespace }).first,
                  let initial = first.first, initial.isUppercase
            else { return nil }
            trimmed = String(first)
            while let last = trimmed.last, ".,;:'’".contains(last) { trimmed.removeLast() }
        }

        let lowered = trimmed.lowercased()
        guard lowered.count >= 3 else { return nil }

        // "The Man" and "her brother" are labels made entirely of words the
        // story is going to be full of. Matching them would draw a line from
        // everyone to everyone.
        let words = lowered
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !words.isEmpty, words.contains(where: { !stopwords.contains($0) }) else { return nil }

        return trimmed
    }

    /// What to look for when hunting a strand's label in someone else's answer,
    /// or nil if this label cannot be looked for at all.
    static func needle(for label: String) -> [UInt8]? {
        matchable(for: label).map { Array($0.lowercased().utf8) }
    }

    /// Whether `needle` appears in `haystack` as a whole word. Both must already
    /// be lowercased UTF-8 bytes.
    static func mentions(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }

        // Deliberately a byte scan and not range(of:options:.caseInsensitive):
        // that routes through ICU at about a microsecond a call, and this runs
        // once per block per character every time the deck is dealt.
        var start = 0
        while start <= haystack.count - needle.count {
            if haystack[start] == needle[0] {
                var i = 1
                while i < needle.count, haystack[start + i] == needle[i] { i += 1 }
                if i == needle.count {
                    let end = start + needle.count
                    let beforeOK = start == 0 || !isWordByte(haystack[start - 1])
                    let afterOK = end == haystack.count || !isWordByte(haystack[end])
                    if beforeOK && afterOK { return true }
                }
            }
            start += 1
        }
        return false
    }

    // MARK: - Building

    /// Every connection in the story, strongest first.
    public static func edges(_ project: Project) -> [WebEdge] {
        let characters = project.strands.filter { $0.type == .character }
        guard characters.count >= 2 else { return [] }

        let needles: [(id: String, bytes: [UInt8])] = characters.compactMap { strand in
            needle(for: strand.label).map { (strand.id, $0) }
        }
        let characterIds = Set(characters.map(\.id))

        var mentionCounts: [String: Int] = [:]
        var pairCounts: [String: Int] = [:]

        func key(_ x: String, _ y: String) -> String { x < y ? "\(x)::\(y)" : "\(y)::\(x)" }

        for block in project.blocks {
            // A block asked about two people is a connection by construction.
            if let about = block.aboutStrandId,
               characterIds.contains(block.strandId), characterIds.contains(about),
               about != block.strandId {
                pairCounts[key(block.strandId, about), default: 0] += 1
            }

            let answer = block.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { continue }
            // Only the answer, never the prompt: a prompt names its own subject
            // by construction, so scanning prompts would have every block prove
            // a link to itself.
            let haystack = Array(answer.lowercased().utf8)

            var hits: [(id: String, bytes: [UInt8])] = []
            for (id, bytes) in needles where id != block.strandId {
                if mentions(haystack, bytes) { hits.append((id, bytes)) }
            }
            // "Marla Vance" contains "Marla", so a sentence naming the first
            // matches both. Keep the longer name only — the shorter one is an
            // artefact of the longer, not a second person in the sentence.
            //
            // Strictly longer: two characters who happen to share a label each
            // contain the other, and dropping both would leave the sentence
            // naming nobody.
            let named = hits
                .filter { hit in
                    !hits.contains { $0.bytes.count > hit.bytes.count && mentions($0.bytes, hit.bytes) }
                }
                .map(\.id)
            guard !named.isEmpty else { continue }

            if characterIds.contains(block.strandId) {
                // Written about Marla, naming Howard.
                for id in named { mentionCounts[key(block.strandId, id), default: 0] += 1 }
            }
            // Two names in one sentence connect them wherever that sentence
            // lives — "Marla and Howard were partners once" is on the premise,
            // and "Marla confronts Howard at the diner" is on a scene.
            for (i, first) in named.enumerated() {
                for second in named[(i + 1)...] {
                    mentionCounts[key(first, second), default: 0] += 1
                }
            }
        }

        var edges: [WebEdge] = []
        for pairKey in Set(mentionCounts.keys).union(pairCounts.keys) {
            let parts = pairKey.components(separatedBy: "::")
            guard parts.count == 2 else { continue }
            edges.append(
                WebEdge(
                    a: parts[0],
                    b: parts[1],
                    mentions: mentionCounts[pairKey] ?? 0,
                    pairBlocks: pairCounts[pairKey] ?? 0
                )
            )
        }

        return edges.sorted { x, y in
            if x.pairBlocks != y.pairBlocks { return x.pairBlocks > y.pairBlocks }
            if x.mentions != y.mentions { return x.mentions > y.mentions }
            return x.id < y.id
        }
    }

    /// The ordered pairs the deck may ask about: every edge, both ways round.
    /// What Marla thinks of Howard and what Howard thinks of Marla are two
    /// different sentences, and the difference between them is the point.
    public static func orderedPairs(_ project: Project) -> [(subject: String, about: String)] {
        guard isOpen(project) else { return [] }
        return edges(project).flatMap { [($0.a, $0.b), ($0.b, $0.a)] }
    }
}
