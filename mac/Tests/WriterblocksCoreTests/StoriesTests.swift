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
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "Marla.")

        XCTAssertEqual(p.strands.first { $0.type == .character }?.label, "Marla")
    }

    func testSpawnsNothingWhenTheWriterIsNotSureYet() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
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
}
