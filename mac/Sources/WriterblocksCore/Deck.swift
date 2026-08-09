import Foundation

/// Choosing what to ask next.
public enum Deck {

    /// Skips are recorded per strand, not per question: skipping "what do you
    /// like about Marla?" must not also push the question back for Jim.
    ///
    /// A question asked about two people carries the other one too, or asking
    /// what Marla thinks of Howard would count as having asked what she thinks
    /// of everybody. The two-part form is left exactly as it was: every story
    /// file already on disk is full of those keys.
    public static func skipKey(_ strandId: String, _ questionId: String, about: String? = nil) -> String {
        guard let about else { return "\(strandId)::\(questionId)" }
        return "\(strandId)::\(questionId)::\(about)"
    }

    /// How many blocks the two of them already have between them, in this
    /// direction.
    static func pairKey(_ strandId: String, _ aboutStrandId: String) -> String {
        "\(strandId)::\(aboutStrandId)"
    }

    public static func render(_ text: String, for strand: Strand, about: Strand? = nil) -> String {
        var out = text.replacingOccurrences(of: "{subject}", with: strand.label)
        if let about { out = out.replacingOccurrences(of: "{other}", with: about.label) }
        return out
    }

    /// How many blocks the writer has to lay down before a skipped question
    /// comes back.
    ///
    /// This is deliberately measured in blocks rather than in priority: every
    /// answer can spawn a new subject carrying two dozen fresh questions, so any
    /// fixed priority penalty — however large — can be outrun forever, and "skip
    /// for now" would quietly become "never again".
    static let skipCooldownBlocks = 8

    /// Sinks a question below everything else without removing it from the deck.
    static let skipPenalty = 1000

    // MARK: - Tally

    /// One pass over the blocks, so choosing a question stays linear in the size
    /// of the project rather than scanning every block once per strand per
    /// question.
    private struct Tally {
        /// `strandId::questionId` -> times asked, whether or not it got an answer.
        var asked: [String: Int] = [:]
        /// `strandId::questionId` -> times it came back with an actual sentence.
        var answered: [String: Int] = [:]
        /// strandId -> how many blocks hang off it.
        var perStrand: [String: Int] = [:]
        /// `strandId::aboutStrandId` -> blocks written about that ordered pair.
        var perPair: [String: Int] = [:]
    }

    private static func tally(_ project: Project) -> Tally {
        var t = Tally()
        for block in project.blocks {
            t.perStrand[block.strandId, default: 0] += 1
            if let about = block.aboutStrandId {
                t.perPair[pairKey(block.strandId, about), default: 0] += 1
            }
            guard let questionId = block.questionId else { continue }
            // Keyed off the block's own link rather than off its template:
            // deleting a character nulls the link and leaves a pair question
            // behind with no other, and that block must match nothing rather
            // than count against some innocent pair.
            let key = skipKey(block.strandId, questionId, about: block.aboutStrandId)
            t.asked[key, default: 0] += 1
            if !block.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                t.answered[key, default: 0] += 1
            }
        }
        return t
    }

    /// A gated question opens only once a parent has been genuinely answered for
    /// the same strand. "Not sure yet" does not open it — there is no point
    /// asking whether they like a job we have not named.
    private static func isUnlocked(_ t: Tally, _ template: QuestionTemplate, _ strand: Strand) -> Bool {
        guard Questions.gatedIds.contains(template.id) else { return true }
        return Questions.parentsOf(template.id).contains { parentId in
            (t.answered[skipKey(strand.id, parentId)] ?? 0) > 0
        }
    }

    // MARK: - Candidates

    private struct Candidate {
        let template: QuestionTemplate
        let strand: Strand
        /// The second character, for a pair question.
        let about: Strand?
        /// Repeatable questions drift later each time they are used, so they never dominate.
        let effectivePriority: Int
        /// How much is already written about this subject — the strand for an
        /// ordinary question, the pair for a pair question.
        let spreadWeight: Int
    }

    private static func candidates(_ project: Project) -> [Candidate] {
        let t = tally(project)
        var out: [Candidate] = []

        func stillCoolingOff(_ key: String) -> Bool {
            guard let skippedAt = project.skipped[key] else { return false }
            return project.blocks.count - skippedAt < skipCooldownBlocks
        }

        for strand in project.strands {
            let strandBlocks = t.perStrand[strand.id] ?? 0

            for template in Questions.all where template.strandType == strand.type {
                // Pair questions are character questions, so they turn up here
                // too. Dealt from this loop they would have no "other" and
                // would store {other} unsubstituted on the block, where it
                // would be read back in the outline for ever.
                if template.isPair { continue }

                let key = skipKey(strand.id, template.id)
                let asked = t.asked[key] ?? 0
                if asked > 0 && !template.isRepeatable { continue }
                if !isUnlocked(t, template, strand) { continue }

                out.append(
                    Candidate(
                        template: template,
                        strand: strand,
                        about: nil,
                        effectivePriority: template.priority
                            + (template.isRepeatable ? asked * 5 : 0)
                            + (stillCoolingOff(key) ? skipPenalty : 0),
                        spreadWeight: strandBlocks
                    )
                )
            }
        }

        let pairTemplates = Questions.all.filter(\.isPair)
        if !pairTemplates.isEmpty {
            let byId = Dictionary(project.strands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Only pairs the story has actually connected, and only once there
            // is enough of a story to have connected them. Real casts are
            // sparse, so this stays proportional to the lines on the web rather
            // than to every possible pairing.
            for pair in Webs.orderedPairs(project) {
                guard let subject = byId[pair.subject], let about = byId[pair.about] else { continue }
                let pairBlocks = t.perPair[pairKey(subject.id, about.id)] ?? 0

                for template in pairTemplates {
                    let key = skipKey(subject.id, template.id, about: about.id)
                    let asked = t.asked[key] ?? 0
                    if asked > 0 && !template.isRepeatable { continue }

                    out.append(
                        Candidate(
                            template: template,
                            strand: subject,
                            about: about,
                            effectivePriority: template.priority
                                + (template.isRepeatable ? asked * 5 : 0)
                                // Every pair template would otherwise come due
                                // for every pair at once, and the writer would
                                // get five questions about Marla and Howard in
                                // a row. Drifting on pair depth interleaves
                                // them with everything else.
                                + pairBlocks * 4
                                + (stillCoolingOff(key) ? skipPenalty : 0),
                            spreadWeight: pairBlocks
                        )
                    )
                }
            }
        }

        return out
    }

    private static func isBefore(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.effectivePriority != b.effectivePriority {
            return a.effectivePriority < b.effectivePriority
        }
        // Same question, several subjects: ask about the thinnest one, so the
        // web grows outward instead of burrowing into whoever came first.
        if a.spreadWeight != b.spreadWeight { return a.spreadWeight < b.spreadWeight }
        if a.strand.order != b.strand.order { return a.strand.order < b.strand.order }
        if a.template.id != b.template.id { return a.template.id < b.template.id }
        // Same question about the same person, different other. Without this
        // the winner would be whichever way round the strands happen to sit.
        let ao = a.about?.order ?? -1
        let bo = b.about?.order ?? -1
        if ao != bo { return ao < bo }
        return (a.about?.id ?? "") < (b.about?.id ?? "")
    }

    // MARK: - Public

    /// The next thing to ask. `focusStrandId` biases toward one subject ("keep
    /// asking me about Marla") but falls back to the whole deck once that strand
    /// is exhausted, rather than dead-ending.
    public static func nextQuestion(
        _ project: Project,
        focusStrandId: String? = nil,
        focusAboutStrandId: String? = nil
    ) -> DealtQuestion? {
        let all = candidates(project)
        if all.isEmpty { return nil }

        var pool = all
        if let focusStrandId {
            let narrowed = all.filter { candidate in
                candidate.strand.id == focusStrandId
                    && (focusAboutStrandId == nil || candidate.about?.id == focusAboutStrandId)
            }
            if !narrowed.isEmpty { pool = narrowed }
        }

        guard let best = pool.min(by: isBefore) else { return nil }
        return DealtQuestion(
            template: best.template,
            strand: best.strand,
            text: render(best.template.text, for: best.strand, about: best.about),
            about: best.about
        )
    }

    /// Whether a question already on screen is still the question it was.
    ///
    /// The point of asking is to be able to leave the writer alone. Adding a
    /// character mid-sentence — which is exactly what naming a new one from the
    /// answer field does — puts a brand new strand in front of the deck, and a
    /// fresh character wins on priority against almost anything, so re-dealing
    /// would swap the question out from under a half-written answer. Worse, the
    /// question is stored on the block when the answer is submitted and read
    /// back in the outline for ever, so the sentence would be filed under
    /// something the writer never saw.
    ///
    /// A label change counts as stale on purpose: the question was rendered
    /// with the old name in it, so it has to be dealt again to catch up.
    public static func isStillDealable(_ project: Project, _ dealt: DealtQuestion) -> Bool {
        func unchanged(_ strand: Strand) -> Bool {
            project.strands.contains { $0.id == strand.id && $0.label == strand.label }
        }
        guard unchanged(dealt.strand) else { return false }
        if let about = dealt.about, !unchanged(about) { return false }
        return true
    }

    /// Deal one particular question, for the callers that already know what they
    /// want to ask rather than letting the deck choose. Returns nil if the
    /// question or either strand is gone.
    public static func deal(
        _ project: Project,
        questionId: String,
        strandId: String,
        aboutStrandId: String? = nil
    ) -> DealtQuestion? {
        guard let template = Questions.question(questionId),
              let strand = project.strands.first(where: { $0.id == strandId })
        else { return nil }

        var about: Strand?
        if let aboutStrandId {
            guard let found = project.strands.first(where: { $0.id == aboutStrandId }) else { return nil }
            about = found
        }

        return DealtQuestion(
            template: template,
            strand: strand,
            text: render(template.text, for: strand, about: about),
            about: about
        )
    }

    /// How many questions are still on the table — for the "you are not empty" counter.
    public static func remainingCount(_ project: Project) -> Int {
        candidates(project).count
    }
}
