import XCTest
@testable import WriterblocksCore

final class StoriesTests: XCTestCase {

    private func question(_ id: String) throws -> QuestionTemplate {
        try XCTUnwrap(Questions.question(id))
    }

    private func answers(_ project: Project, strandId: String) -> [String] {
        Stories.blocks(of: project, strandId: strandId).map(\.answer)
    }

    // MARK: - labelFromAnswer

    func testStripsTrailingPunctuationAndCollapsesWhitespace() {
        XCTAssertEqual(Stories.labelFromAnswer("  The   diner.  "), "The diner")
    }

    func testClipsALongAnswerInsteadOfRejectingIt() {
        let label = Stories.labelFromAnswer(String(repeating: "a", count: 120))
        XCTAssertLessThanOrEqual(label.count, 40)
        XCTAssertTrue(label.hasSuffix("…"))
    }

    func testFallsBackRatherThanProducingAnEmptyName() {
        XCTAssertEqual(Stories.labelFromAnswer("   "), "Untitled")
    }

    // MARK: - applyAnswer

    func testSpawnsAStrandNamedFromTheAnswer() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "The Wreck")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "Marla.")

        XCTAssertEqual(p.strands.first { $0.type == .character }?.label, "Marla")
    }

    func testNamesTheProjectFromTheNamingQuestion() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A diver goes back for the wreck.")
        XCTAssertEqual(p.title, "Untitled story")

        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "The Wreck")
        XCTAssertEqual(p.title, "The Wreck")
    }

    func testLeavesTheTitleAloneWhenTheWriterIsNotSureWhatToCallIt() throws {
        var p = Stories.createProject(title: "A diver goes back for the wreck.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "   ")

        // Not "Untitled story": a blank answer must not throw away the name the
        // story already had.
        XCTAssertEqual(p.title, "A diver goes back for the wreck.")
        XCTAssertTrue(p.blocks.contains { $0.questionId == "story-name" && $0.answer.isEmpty })
    }

    func testSpawnsNothingWhenTheWriterIsNotSureYet() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "The Wreck")
        let before = p.strands.count
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "")

        XCTAssertEqual(p.strands.count, before)
        // The question is still recorded, as an open thread.
        XCTAssertTrue(p.blocks.contains { $0.questionId == "main-character" && $0.answer.isEmpty })
    }

    func testCarriesTheBeatThroughToTheBlock() throws {
        var p = Stories.createProject()
        let scene = try XCTUnwrap(p.strands.first { $0.type == .scene })
        let first = try question("scene-first")
        p = Stories.applyAnswer(
            p, DealtQuestion(template: first, strand: scene, text: "First scene?"), "A boat."
        )

        XCTAssertEqual(p.blocks.first?.beat, first.beat)
        XCTAssertNotNil(first.beat)
    }

    func testRecordsTheQuestionWithTheNameAlreadyFilledIn() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "The Wreck")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "Marla")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })

        let dealt = DealtQuestion(
            template: try question("char-like"),
            strand: marla,
            text: Deck.render(try question("char-like").text, for: marla)
        )
        p = Stories.applyAnswer(p, dealt, "She never apologises.")

        let block = try XCTUnwrap(p.blocks.last)
        XCTAssertEqual(block.prompt, "What do you like about Marla?")
        XCTAssertFalse(block.prompt.contains("{subject}"))
    }

    func testGivesEachNewBlockTheNextOrderInItsStrand() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "one")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "two")
        let premise = try XCTUnwrap(p.strands.first { $0.type == .premise })

        XCTAssertEqual(answers(p, strandId: premise.id), ["one", "two"])
    }

    // MARK: - Board edits

    func testRenamesAStrandAndRefusesABlankName() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        let strand = try XCTUnwrap(p.strands.first { $0.label == "Marla" })

        p = Stories.renameStrand(p, strandId: strand.id, label: "  Marla Vance  ")
        XCTAssertEqual(p.strands.first { $0.id == strand.id }?.label, "Marla Vance")

        p = Stories.renameStrand(p, strandId: strand.id, label: "   ")
        XCTAssertEqual(p.strands.first { $0.id == strand.id }?.label, "Marla Vance")
    }

    func testDeletesAStrandAlongWithItsBlocks() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        let strand = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        p = Stories.addFreeBlock(p, strandId: strand.id, answer: "She hums when she lies.")
        XCTAssertEqual(p.blocks.count, 1)

        p = Stories.deleteStrand(p, strandId: strand.id)
        XCTAssertFalse(p.strands.contains { $0.id == strand.id })
        XCTAssertTrue(p.blocks.isEmpty)
    }

    // MARK: - Renaming the story

    private func named(_ title: String) throws -> Project {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), title)
        return p
    }

    private func namingAnswer(_ p: Project) -> String? {
        p.blocks.first { $0.questionId == "story-name" }?.answer
    }

    func testRenamingAlsoFixesTheAnswerThatNamedIt() throws {
        // Otherwise the outline reads "Okay — what's it called? The Wreck"
        // underneath a story titled Deep Water.
        var p = try named("The Wreck")
        XCTAssertEqual(p.title, "The Wreck")

        p = Stories.retitle(p, title: "Deep Water")
        XCTAssertEqual(p.title, "Deep Water")
        XCTAssertEqual(namingAnswer(p), "Deep Water")
    }

    func testRenamingLeavesAnAnswerTheWriterHasAlreadyChanged() throws {
        // They have pulled the two apart on purpose. That sentence is theirs.
        var p = try named("The Wreck")
        let block = try XCTUnwrap(p.blocks.first { $0.questionId == "story-name" })
        p = Stories.editBlock(p, blockId: block.id, answer: "Something else entirely")

        p = Stories.retitle(p, title: "Deep Water")
        XCTAssertEqual(p.title, "Deep Water")
        XCTAssertEqual(namingAnswer(p), "Something else entirely")
    }

    func testRenamingTwiceKeepsBothInStep() throws {
        var p = try named("The Wreck")
        p = Stories.retitle(p, title: "Deep Water")
        p = Stories.retitle(p, title: "Salvage")

        XCTAssertEqual(p.title, "Salvage")
        XCTAssertEqual(namingAnswer(p), "Salvage")
    }

    func testWillNotUnnameAStory() throws {
        // Clearing the field and pressing return is a slip, not a request to
        // call the story "Untitled story".
        let p = try named("The Wreck")
        XCTAssertEqual(Stories.retitle(p, title: "   ").title, "The Wreck")
        XCTAssertEqual(Stories.retitle(p, title: "").title, "The Wreck")
    }

    func testRenamingAStoryThatWasNeverAskedItsNameStillWorks() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.retitle(p, title: "Deep Water")
        XCTAssertEqual(p.title, "Deep Water")
    }

    // MARK: - Linking two characters

    func testDrawingALinkOpensAQuestionAboutTheTwoOfThem() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Howard")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let howard = try XCTUnwrap(p.strands.first { $0.label == "Howard" })

        p = Stories.linkCharacters(p, strandId: marla.id, aboutStrandId: howard.id)

        let block = try XCTUnwrap(p.blocks.last)
        XCTAssertEqual(block.strandId, marla.id)
        XCTAssertEqual(block.aboutStrandId, howard.id)
        // An open thread, which is what a line the writer drew actually is.
        XCTAssertTrue(block.answer.isEmpty)
        // Both names are already in the prompt, so it reads correctly in the
        // outline without anything else having to know about the link.
        XCTAssertTrue(block.prompt.contains("Marla"))
        XCTAssertTrue(block.prompt.contains("Howard"))
        XCTAssertFalse(block.prompt.contains("{"))
    }

    func testDrawingTheSameLinkTwiceChangesNothing() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Howard")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let howard = try XCTUnwrap(p.strands.first { $0.label == "Howard" })

        p = Stories.linkCharacters(p, strandId: marla.id, aboutStrandId: howard.id)
        let after = Stories.linkCharacters(p, strandId: marla.id, aboutStrandId: howard.id)
        XCTAssertEqual(after.blocks.count, 1)

        // And neither does drawing it back the other way: they are connected.
        let reversed = Stories.linkCharacters(p, strandId: howard.id, aboutStrandId: marla.id)
        XCTAssertEqual(reversed.blocks.count, 1)
    }

    func testRefusesLinksThatAreNotBetweenTwoCharacters() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .setting, label: "The harbour")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let harbour = try XCTUnwrap(p.strands.first { $0.label == "The harbour" })

        XCTAssertTrue(Stories.linkCharacters(p, strandId: marla.id, aboutStrandId: harbour.id).blocks.isEmpty)
        XCTAssertTrue(Stories.linkCharacters(p, strandId: marla.id, aboutStrandId: marla.id).blocks.isEmpty)
        XCTAssertTrue(Stories.linkCharacters(p, strandId: marla.id, aboutStrandId: "gone").blocks.isEmpty)
    }

    func testKeepsTheSentenceWhenTheCharacterItWasAboutIsDeleted() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Howard")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let howard = try XCTUnwrap(p.strands.first { $0.label == "Howard" })

        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She still owes him.")
        let blockId = try XCTUnwrap(p.blocks.first).id
        p.blocks[0].aboutStrandId = howard.id

        p = Stories.deleteStrand(p, strandId: howard.id)

        let block = try XCTUnwrap(p.blocks.first { $0.id == blockId })
        XCTAssertEqual(block.answer, "She still owes him.")
        XCTAssertNil(block.aboutStrandId, "a link to a deleted strand must not survive")
    }

    func testDroppingAPairBlockInAnotherColumnBreaksItsLink() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Howard")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let howard = try XCTUnwrap(p.strands.first { $0.label == "Howard" })

        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She still owes him.")
        let blockId = try XCTUnwrap(p.blocks.first).id
        p.blocks[0].aboutStrandId = howard.id

        // Dropped onto Howard, the block would otherwise claim to be about
        // Howard from Howard's own side.
        p = Stories.moveBlock(p, blockId: blockId, toStrandId: howard.id, toIndex: 0)

        let block = try XCTUnwrap(p.blocks.first { $0.id == blockId })
        XCTAssertEqual(block.strandId, howard.id)
        XCTAssertNil(block.aboutStrandId)
    }

    func testKeepsTheLinkWhenAPairBlockIsJustReorderedInItsOwnColumn() throws {
        var p = Stories.addStrand(Stories.createProject(), type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Howard")
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let howard = try XCTUnwrap(p.strands.first { $0.label == "Howard" })

        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "one")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "two")
        let blockId = try XCTUnwrap(p.blocks.first).id
        p.blocks[0].aboutStrandId = howard.id

        p = Stories.moveBlock(p, blockId: blockId, toStrandId: marla.id, toIndex: 1)

        XCTAssertEqual(p.blocks.first { $0.id == blockId }?.aboutStrandId, howard.id)
    }

    func testEditsAndDeletesABlock() throws {
        var p = Stories.createProject()
        let premise = try XCTUnwrap(p.strands.first { $0.type == .premise })
        p = Stories.addFreeBlock(p, strandId: premise.id, answer: "first thought")
        let block = try XCTUnwrap(p.blocks.first)

        p = Stories.editBlock(p, blockId: block.id, answer: "  second thought  ")
        XCTAssertEqual(p.blocks.first?.answer, "second thought")

        p = Stories.deleteBlock(p, blockId: block.id)
        XCTAssertTrue(p.blocks.isEmpty)
    }

    // MARK: - moveBlock

    private func threeBlocks() throws -> (project: Project, strandId: String, otherId: String) {
        var p = Stories.createProject()
        p = Stories.addStrand(p, type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Jim")
        let strandId = try XCTUnwrap(p.strands.first { $0.label == "Marla" }).id
        let otherId = try XCTUnwrap(p.strands.first { $0.label == "Jim" }).id
        p = Stories.addFreeBlock(p, strandId: strandId, answer: "a")
        p = Stories.addFreeBlock(p, strandId: strandId, answer: "b")
        p = Stories.addFreeBlock(p, strandId: strandId, answer: "c")
        return (p, strandId, otherId)
    }

    func testReordersWithinAStrand() throws {
        let (project, strandId, _) = try threeBlocks()
        let c = try XCTUnwrap(project.blocks.first { $0.answer == "c" })
        let moved = Stories.moveBlock(project, blockId: c.id, toStrandId: strandId, toIndex: 0)

        XCTAssertEqual(answers(moved, strandId: strandId), ["c", "a", "b"])
    }

    func testMovesABlockToAnotherStrandAndRenumbersBoth() throws {
        let (project, strandId, otherId) = try threeBlocks()
        let b = try XCTUnwrap(project.blocks.first { $0.answer == "b" })
        let moved = Stories.moveBlock(project, blockId: b.id, toStrandId: otherId, toIndex: 0)

        XCTAssertEqual(answers(moved, strandId: strandId), ["a", "c"])
        XCTAssertEqual(answers(moved, strandId: otherId), ["b"])
        XCTAssertEqual(
            Stories.blocks(of: moved, strandId: strandId).map(\.order), [0, 1],
            "order must stay a dense run"
        )
    }

    func testClampsAnOutOfRangeIndexInsteadOfDroppingTheBlock() throws {
        let (project, strandId, _) = try threeBlocks()
        let a = try XCTUnwrap(project.blocks.first { $0.answer == "a" })
        let moved = Stories.moveBlock(project, blockId: a.id, toStrandId: strandId, toIndex: 99)

        XCTAssertEqual(answers(moved, strandId: strandId), ["b", "c", "a"])
    }

    func testIgnoresAMoveToAStrandThatDoesNotExist() throws {
        let (project, _, _) = try threeBlocks()
        let a = try XCTUnwrap(project.blocks.first { $0.answer == "a" })

        XCTAssertEqual(Stories.moveBlock(project, blockId: a.id, toStrandId: "nope", toIndex: 0), project)
    }

    // MARK: - Dropping into a gap on the board
    //
    // The board drops into the gaps *between* cards, so its index counts the
    // column as displayed — including the card being dragged. Getting this
    // off-by-one wrong makes a block land one position from where the insertion
    // line promised, which is worse than no indicator at all.

    func testDroppingIntoTheGapBelowItselfLandsWhereTheLineShowed() throws {
        let (project, strandId, _) = try threeBlocks()
        let a = try XCTUnwrap(project.blocks.first { $0.answer == "a" })

        // [a, b, c] — drop "a" into the gap between b and c (display index 2).
        let moved = Stories.moveBlock(
            project, blockId: a.id, toStrandId: strandId, toDisplayIndex: 2
        )
        XCTAssertEqual(answers(moved, strandId: strandId), ["b", "a", "c"])
    }

    func testDroppingIntoTheGapAboveItselfNeedsNoShift() throws {
        let (project, strandId, _) = try threeBlocks()
        let c = try XCTUnwrap(project.blocks.first { $0.answer == "c" })

        let moved = Stories.moveBlock(
            project, blockId: c.id, toStrandId: strandId, toDisplayIndex: 0
        )
        XCTAssertEqual(answers(moved, strandId: strandId), ["c", "a", "b"])
    }

    func testDroppingIntoTheLastGapMovesToTheEnd() throws {
        let (project, strandId, _) = try threeBlocks()
        let a = try XCTUnwrap(project.blocks.first { $0.answer == "a" })

        let moved = Stories.moveBlock(
            project, blockId: a.id, toStrandId: strandId, toDisplayIndex: 3
        )
        XCTAssertEqual(answers(moved, strandId: strandId), ["b", "c", "a"])
    }

    func testDroppingIntoItsOwnGapChangesNothing() throws {
        let (project, strandId, _) = try threeBlocks()
        let b = try XCTUnwrap(project.blocks.first { $0.answer == "b" })

        for index in [1, 2] {
            let moved = Stories.moveBlock(
                project, blockId: b.id, toStrandId: strandId, toDisplayIndex: index
            )
            XCTAssertEqual(answers(moved, strandId: strandId), ["a", "b", "c"], "gap \(index)")
        }
    }

    func testDroppingIntoAnotherColumnNeedsNoShift() throws {
        let (project, strandId, otherId) = try threeBlocks()
        var p = Stories.addFreeBlock(project, strandId: otherId, answer: "x")
        p = Stories.addFreeBlock(p, strandId: otherId, answer: "y")
        let b = try XCTUnwrap(p.blocks.first { $0.answer == "b" })

        // The dragged block is not in the target column, so display index and
        // insertion index are the same.
        let moved = Stories.moveBlock(p, blockId: b.id, toStrandId: otherId, toDisplayIndex: 1)

        XCTAssertEqual(answers(moved, strandId: otherId), ["x", "b", "y"])
        XCTAssertEqual(answers(moved, strandId: strandId), ["a", "c"])
    }
}
