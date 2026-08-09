import Foundation

/// Every change to a story. All of these are pure `(Project, …) -> Project`, so
/// they test without a UI and without a document.
public enum Stories {

    static let maxLabel = 40

    private static func newId() -> String { UUID().uuidString }

    private static func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    private static func touched(_ project: Project, _ mutate: (inout Project) -> Void) -> Project {
        var copy = project
        mutate(&copy)
        copy.updatedAt = now()
        return copy
    }

    static func blocks(of project: Project, strandId: String) -> [Block] {
        project.blocks.filter { $0.strandId == strandId }.sorted { $0.order < $1.order }
    }

    private static func nextOrder(_ project: Project, _ strandId: String) -> Int {
        (blocks(of: project, strandId: strandId).last?.order).map { $0 + 1 } ?? 0
    }

    /// Turn an answer into a strand name: "A diner off the interstate." becomes
    /// "A diner off the interstate". Long answers are clipped rather than
    /// rejected — the writer can rename the strand on the board.
    public static func labelFromAnswer(_ answer: String) -> String {
        let collapsed = answer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        var cleaned = collapsed
        while let last = cleaned.last, ".,;:".contains(last) {
            cleaned.removeLast()
        }

        if cleaned.isEmpty { return "Untitled" }
        if cleaned.count <= maxLabel { return cleaned }

        let clipped = String(cleaned.prefix(maxLabel - 1))
            .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return clipped + "…"
    }

    public static func createProject(title: String = "Untitled story") -> Project {
        let t = now()
        return Project(
            id: newId(),
            title: title,
            schemaVersion: schemaVersion,
            strands: [
                Strand(id: newId(), type: .premise, label: "Premise", order: 0, createdAt: t),
                Strand(id: newId(), type: .scene, label: "Scenes", order: 1, createdAt: t)
            ],
            blocks: [],
            skipped: [:],
            createdAt: t,
            updatedAt: t
        )
    }

    public static func addStrand(_ project: Project, type: StrandType, label: String) -> Project {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = (project.strands.map(\.order).max()).map { $0 + 1 } ?? 0
        let strand = Strand(
            id: newId(),
            type: type,
            label: trimmed.isEmpty ? "Untitled" : trimmed,
            order: order,
            createdAt: now()
        )
        return touched(project) { $0.strands.append(strand) }
    }

    public static func renameStrand(_ project: Project, strandId: String, label: String) -> Project {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return project }
        return touched(project) { p in
            for i in p.strands.indices where p.strands[i].id == strandId {
                p.strands[i].label = trimmed
            }
        }
    }

    /// Deletes the strand and everything hanging off it.
    public static func deleteStrand(_ project: Project, strandId: String) -> Project {
        touched(project) { p in
            p.strands.removeAll { $0.id == strandId }
            p.blocks.removeAll { $0.strandId == strandId }
            // Blocks elsewhere that were about this one keep their sentence and
            // lose the link. "What does Marla think of Howard?" is still worth
            // reading once Howard is gone; a pointer to nothing is not.
            for i in p.blocks.indices where p.blocks[i].aboutStrandId == strandId {
                p.blocks[i].aboutStrandId = nil
            }
        }
    }

    /// Record an answer. An empty answer is legitimate — it becomes an open
    /// thread that shows up in the outline as a hole, which is more useful than
    /// pretending the question was never asked.
    public static func applyAnswer(_ project: Project, _ dealt: DealtQuestion, _ answer: String) -> Project {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        let block = Block(
            id: newId(),
            strandId: dealt.strand.id,
            questionId: dealt.template.id,
            prompt: dealt.text,
            answer: trimmed,
            beat: dealt.template.beat,
            order: nextOrder(project, dealt.strand.id),
            createdAt: now(),
            aboutStrandId: dealt.about?.id
        )

        var next = touched(project) { p in
            p.blocks.append(block)
            // Answering clears any earlier skip of this question for this strand.
            p.skipped.removeValue(
                forKey: Deck.skipKey(dealt.strand.id, dealt.template.id, about: dealt.about?.id)
            )
        }

        // "Who is the main character?" doesn't just record a block, it opens a
        // new subject to ask about. A blank answer opens nothing.
        if let spawns = dealt.template.spawns, !trimmed.isEmpty {
            next = addStrand(next, type: spawns, label: labelFromAnswer(trimmed))
        }

        // Naming the story is a question like any other. The blank guard matters
        // more here than it does above: renameProject turns an empty title into
        // "Untitled story", so without it "Not sure yet" would rename the story
        // instead of leaving it as it was.
        if dealt.template.titles == true, !trimmed.isEmpty {
            next = renameProject(next, title: labelFromAnswer(trimmed))
        }

        return next
    }

    /// Steps a question aside, remembering how far along the writer was at the time.
    public static func skipQuestion(
        _ project: Project,
        strandId: String,
        questionId: String,
        aboutStrandId: String? = nil
    ) -> Project {
        let key = Deck.skipKey(strandId, questionId, about: aboutStrandId)
        guard project.skipped[key] == nil else { return project }
        return touched(project) { $0.skipped[key] = project.blocks.count }
    }

    /// Connect two characters by hand, by opening the first question about the
    /// two of them.
    ///
    /// The block starts unanswered, which is exactly what a line the writer
    /// drew is: an open thread. It also means drawing a line hands back a
    /// sentence to write rather than a decoration, and the block reads properly
    /// in the outline because both names are already in the prompt.
    ///
    /// Drawing the same line twice does nothing — the pair is already connected
    /// and the deck will keep asking about it on its own.
    public static func linkCharacters(
        _ project: Project,
        strandId: String,
        aboutStrandId: String
    ) -> Project {
        guard strandId != aboutStrandId,
              project.strands.contains(where: { $0.id == strandId && $0.type == .character }),
              project.strands.contains(where: { $0.id == aboutStrandId && $0.type == .character })
        else { return project }

        let alreadyLinked = project.blocks.contains { block in
            (block.strandId == strandId && block.aboutStrandId == aboutStrandId)
                || (block.strandId == aboutStrandId && block.aboutStrandId == strandId)
        }
        guard !alreadyLinked else { return project }

        guard let template = Questions.all
            .filter(\.isPair)
            .min(by: { $0.priority != $1.priority ? $0.priority < $1.priority : $0.id < $1.id }),
            let dealt = Deck.deal(
                project, questionId: template.id, strandId: strandId, aboutStrandId: aboutStrandId
            )
        else { return project }

        return applyAnswer(project, dealt, "")
    }

    /// A block the writer wrote unprompted.
    public static func addFreeBlock(_ project: Project, strandId: String, answer: String) -> Project {
        let block = Block(
            id: newId(),
            strandId: strandId,
            questionId: nil,
            prompt: "",
            answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
            beat: nil,
            order: nextOrder(project, strandId),
            createdAt: now()
        )
        return touched(project) { $0.blocks.append(block) }
    }

    public static func editBlock(_ project: Project, blockId: String, answer: String) -> Project {
        touched(project) { p in
            for i in p.blocks.indices where p.blocks[i].id == blockId {
                p.blocks[i].answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    public static func deleteBlock(_ project: Project, blockId: String) -> Project {
        touched(project) { $0.blocks.removeAll { $0.id == blockId } }
    }

    /// Move a block to `toIndex` within `toStrandId`, renumbering both the
    /// source and destination strands so `order` stays a dense 0..n-1 run.
    public static func moveBlock(
        _ project: Project,
        blockId: String,
        toStrandId: String,
        toIndex: Int
    ) -> Project {
        guard let moving = project.blocks.first(where: { $0.id == blockId }) else { return project }
        guard project.strands.contains(where: { $0.id == toStrandId }) else { return project }

        let fromStrandId = moving.strandId
        let source = blocks(of: project, strandId: fromStrandId).filter { $0.id != blockId }
        let target = fromStrandId == toStrandId ? source : blocks(of: project, strandId: toStrandId)

        let clamped = max(0, min(toIndex, target.count))
        var relocated = moving
        relocated.strandId = toStrandId
        // Dragged to another column, a block about two people is no longer about
        // the pair it was — dropped onto Howard it would claim to be Howard
        // asking about Howard. The prompt already reads as written; only the
        // link has to go.
        if fromStrandId != toStrandId { relocated.aboutStrandId = nil }

        var merged = target
        merged.insert(relocated, at: clamped)

        var renumbered: [String: Block] = [:]
        for (i, var block) in merged.enumerated() {
            block.order = i
            renumbered[block.id] = block
        }
        if fromStrandId != toStrandId {
            for (i, var block) in source.enumerated() {
                block.order = i
                renumbered[block.id] = block
            }
        }

        return touched(project) { p in
            p.blocks = p.blocks.map { renumbered[$0.id] ?? $0 }
        }
    }

    /// Move a block to the gap at `toDisplayIndex`, where the index counts gaps
    /// in the column *as displayed* — which includes the block being dragged
    /// when it started in that column.
    ///
    /// `moveBlock(toIndex:)` inserts into the column with the moved block
    /// already lifted out, so a drop below the block's own position has to shift
    /// down by one. Keeping that off-by-one here rather than in the board means
    /// it is covered by tests.
    public static func moveBlock(
        _ project: Project,
        blockId: String,
        toStrandId: String,
        toDisplayIndex: Int
    ) -> Project {
        guard let moving = project.blocks.first(where: { $0.id == blockId }) else { return project }

        var index = toDisplayIndex
        if moving.strandId == toStrandId {
            let column = blocks(of: project, strandId: toStrandId)
            if let current = column.firstIndex(where: { $0.id == blockId }), current < toDisplayIndex {
                index -= 1
            }
        }

        return moveBlock(project, blockId: blockId, toStrandId: toStrandId, toIndex: index)
    }

    public static func renameProject(_ project: Project, title: String) -> Project {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return touched(project) { $0.title = trimmed.isEmpty ? "Untitled story" : trimmed }
    }

    /// Rename the story the way the writer means it — the title, and the answer
    /// they gave when it asked what to call it.
    ///
    /// Without the second half the outline reads "Okay — what's it called? The
    /// Wreck" underneath a story titled Deep Water, which is a contradiction
    /// nobody asked for.
    ///
    /// But that answer is a sentence the writer wrote, and rewriting those is
    /// not something this app does. So it is only touched when it is provably
    /// where the current title came from — if they have already changed one
    /// without the other, that difference was deliberate and is left alone.
    ///
    /// A blank name is refused outright rather than falling through to
    /// "Untitled story": clearing the field and pressing return is a slip, not
    /// a request to un-name the story.
    public static func retitle(_ project: Project, title: String) -> Project {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.title else { return project }

        let namingIds = Set(Questions.all.filter { $0.titles == true }.map(\.id))
        var next = renameProject(project, title: trimmed)

        for i in next.blocks.indices {
            guard let questionId = next.blocks[i].questionId, namingIds.contains(questionId),
                  labelFromAnswer(next.blocks[i].answer) == project.title
            else { continue }
            next.blocks[i].answer = trimmed
        }

        return next
    }
}
