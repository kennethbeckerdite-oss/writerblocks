import Foundation

/// Choosing what to ask next.
public enum Deck {

    /// Skips are recorded per strand, not per question: skipping "what do you
    /// like about Marla?" must not also push the question back for Jim.
    public static func skipKey(_ strandId: String, _ questionId: String) -> String {
        "\(strandId)::\(questionId)"
    }

    public static func render(_ text: String, for strand: Strand) -> String {
        text.replacingOccurrences(of: "{subject}", with: strand.label)
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
    }

    private static func tally(_ project: Project) -> Tally {
        var t = Tally()
        for block in project.blocks {
            t.perStrand[block.strandId, default: 0] += 1
            guard let questionId = block.questionId else { continue }
            let key = skipKey(block.strandId, questionId)
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
        /// Repeatable questions drift later each time they are used, so they never dominate.
        let effectivePriority: Int
        let strandBlocks: Int
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
                let key = skipKey(strand.id, template.id)
                let asked = t.asked[key] ?? 0
                if asked > 0 && !template.isRepeatable { continue }
                if !isUnlocked(t, template, strand) { continue }

                out.append(
                    Candidate(
                        template: template,
                        strand: strand,
                        effectivePriority: template.priority
                            + (template.isRepeatable ? asked * 5 : 0)
                            + (stillCoolingOff(key) ? skipPenalty : 0),
                        strandBlocks: strandBlocks
                    )
                )
            }
        }

        return out
    }

    private static func isBefore(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.effectivePriority != b.effectivePriority {
            return a.effectivePriority < b.effectivePriority
        }
        // Same question, several strands: ask about the thinnest one, so the web
        // grows outward instead of burrowing into whoever came first.
        if a.strandBlocks != b.strandBlocks { return a.strandBlocks < b.strandBlocks }
        if a.strand.order != b.strand.order { return a.strand.order < b.strand.order }
        return a.template.id < b.template.id
    }

    // MARK: - Public

    /// The next thing to ask. `focusStrandId` biases toward one subject ("keep
    /// asking me about Marla") but falls back to the whole deck once that strand
    /// is exhausted, rather than dead-ending.
    public static func nextQuestion(_ project: Project, focusStrandId: String? = nil) -> DealtQuestion? {
        let all = candidates(project)
        if all.isEmpty { return nil }

        let pool: [Candidate]
        if let focusStrandId, all.contains(where: { $0.strand.id == focusStrandId }) {
            pool = all.filter { $0.strand.id == focusStrandId }
        } else {
            pool = all
        }

        guard let best = pool.min(by: isBefore) else { return nil }
        return DealtQuestion(
            template: best.template,
            strand: best.strand,
            text: render(best.template.text, for: best.strand)
        )
    }

    /// Deal one particular question, for the callers that already know what they
    /// want to ask rather than letting the deck choose. Returns nil if the
    /// question or the strand is gone.
    public static func deal(_ project: Project, questionId: String, strandId: String) -> DealtQuestion? {
        guard let template = Questions.question(questionId),
              let strand = project.strands.first(where: { $0.id == strandId })
        else { return nil }
        return DealtQuestion(template: template, strand: strand, text: render(template.text, for: strand))
    }

    /// How many questions are still on the table — for the "you are not empty" counter.
    public static func remainingCount(_ project: Project) -> Int {
        candidates(project).count
    }
}
