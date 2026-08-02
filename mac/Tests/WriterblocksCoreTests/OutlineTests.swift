import XCTest
@testable import WriterblocksCore

final class OutlineTests: XCTestCase {

    private func question(_ id: String) throws -> QuestionTemplate {
        try XCTUnwrap(Questions.question(id))
    }

    private func answerScene(_ project: Project, _ questionId: String, _ answer: String) throws -> Project {
        let scene = try XCTUnwrap(project.strands.first { $0.type == .scene })
        let template = try question(questionId)
        return Stories.applyAnswer(
            project,
            DealtQuestion(template: template, strand: scene, text: template.text),
            answer
        )
    }

    /// A premise, one character and one place, each with at least one block on
    /// it — a strand with no blocks is deliberately left out of the outline, so
    /// the fixture has to give them one.
    private func sample() throws -> Project {
        var p = Stories.createProject(title: "The Wreck")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A diver goes back for the wreck.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "Marla")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A harbour town")

        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let town = try XCTUnwrap(p.strands.first { $0.label == "A harbour town" })
        p = Stories.applyAnswer(
            p,
            DealtQuestion(template: try question("char-like"), strand: marla, text: "What do you like about Marla?"),
            "She never apologises."
        )
        p = Stories.applyAnswer(
            p,
            DealtQuestion(template: try question("place-smell"), strand: town, text: "What does A harbour town smell like?"),
            "Diesel and cold rope."
        )
        return p
    }

    // MARK: - Sections

    func testMapsScenesIntoTheStructureSection() {
        XCTAssertEqual(sectionForStrandType(.scene), .structure)
        XCTAssertEqual(sectionForStrandType(.premise), .premise)
        XCTAssertEqual(sectionForStrandType(.character), .character)
        XCTAssertEqual(sectionForStrandType(.setting), .setting)
    }

    func testIsEmptyForAProjectWithNoBlocks() {
        XCTAssertTrue(OutlineBuilder.build(Stories.createProject()).isEmpty)
    }

    func testOrdersSectionsPremiseCharactersPlacesStructure() throws {
        var p = try sample()
        p = try answerScene(p, "scene-first", "She signs the salvage papers.")

        XCTAssertEqual(
            OutlineBuilder.build(p).map(\.section),
            [.premise, .character, .setting, .structure]
        )
    }

    func testGivesEveryCharacterItsOwnGroupHeadedByName() throws {
        var p = try sample()
        p = Stories.addStrand(p, type: .character, label: "Jim")
        let jim = try XCTUnwrap(p.strands.first { $0.label == "Jim" })
        p = Stories.addFreeBlock(p, strandId: jim.id, answer: "He apologises constantly.")

        let characters = try XCTUnwrap(OutlineBuilder.build(p).first { $0.section == .character })
        XCTAssertEqual(characters.groups.map(\.heading), ["Marla", "Jim"])
    }

    func testLeavesOutStrandsThatHaveNoBlocksYet() throws {
        var p = try sample()
        p = Stories.addStrand(p, type: .character, label: "Nobody")

        let characters = OutlineBuilder.build(p).first { $0.section == .character }
        XCTAssertFalse((characters?.groups.compactMap(\.heading) ?? []).contains("Nobody"))
    }

    func testSortsScenesByBeatNoMatterWhatOrderTheyWereAnsweredIn() throws {
        var p = Stories.createProject(title: "Backwards")
        p = try answerScene(p, "scene-last", "She lets the boat go.")
        p = try answerScene(p, "scene-first", "She signs the salvage papers.")
        p = try answerScene(p, "scene-midpoint", "She finds the second body.")

        let structure = try XCTUnwrap(OutlineBuilder.build(p).first { $0.section == .structure })
        XCTAssertEqual(
            structure.groups.first?.blocks.map(\.answer),
            ["She signs the salvage papers.", "She finds the second body.", "She lets the boat go."]
        )
    }

    func testSeparatesScenesWithNoPlaceInTheChronologyYet() throws {
        var p = Stories.createProject()
        p = try answerScene(p, "scene-first", "She signs the papers.")
        p = try answerScene(p, "scene-dreading", "Telling the mother.")

        let structure = try XCTUnwrap(OutlineBuilder.build(p).first { $0.section == .structure })
        XCTAssertEqual(structure.groups.count, 2)
        XCTAssertNil(structure.groups.first?.heading)
        XCTAssertEqual(structure.groups.last?.heading, "Scenes not yet placed")
        XCTAssertEqual(structure.groups.last?.blocks.map(\.answer), ["Telling the mother."])
    }

    func testFollowsABlockThatWasDraggedToAnotherStrand() throws {
        var p = try sample()
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let scene = try XCTUnwrap(p.strands.first { $0.type == .scene })
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She hums when she lies.")
        let block = try XCTUnwrap(p.blocks.first { $0.answer == "She hums when she lies." })

        p = Stories.moveBlock(p, blockId: block.id, toStrandId: scene.id, toIndex: 0)

        let outline = OutlineBuilder.build(p)
        let characterText = (outline.first { $0.section == .character }?.groups ?? [])
            .flatMap { $0.blocks.map(\.answer) }
        let structureText = (outline.first { $0.section == .structure }?.groups ?? [])
            .flatMap { $0.blocks.map(\.answer) }

        XCTAssertFalse(characterText.contains("She hums when she lies."))
        XCTAssertTrue(structureText.contains("She hums when she lies."))
    }

    // MARK: - Stats

    func testCountsBlocksOpenThreadsAndStrands() throws {
        var p = try sample()
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        p = Stories.applyAnswer(
            p,
            DealtQuestion(template: try question("char-afraid"), strand: marla, text: "Afraid?"),
            ""
        )

        let s = OutlineBuilder.stats(p)
        XCTAssertEqual(s.blocks, 6)
        XCTAssertEqual(s.answered, 5)
        XCTAssertEqual(s.open, 1)
        XCTAssertEqual(s.characters, 1)
        XCTAssertEqual(s.settings, 1)
    }

    // MARK: - Markdown

    func testRendersHeadingsSubHeadingsAndPromptLedLines() throws {
        var p = try sample()
        p = try answerScene(p, "scene-first", "She signs the salvage papers.")
        let md = Markdown.render(p)

        XCTAssertTrue(md.hasPrefix("# The Wreck\n"))
        XCTAssertTrue(md.contains("## Premise"))
        XCTAssertTrue(md.contains("## Characters"))
        XCTAssertTrue(md.contains("### Marla"))
        XCTAssertTrue(md.contains("## Shape of the story"))
        XCTAssertTrue(md.contains("- _Who is the main character?_ Marla"))
        XCTAssertTrue(md.hasSuffix("\n"))
        XCTAssertFalse(md.contains("\n\n\n"))
    }

    func testShowsOpenThreadsHonestlyInsteadOfHidingThem() throws {
        var p = try sample()
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        p = Stories.applyAnswer(
            p,
            DealtQuestion(template: try question("char-afraid"), strand: marla, text: "Afraid?"),
            ""
        )

        XCTAssertTrue(Markdown.render(p).contains("**still open**"))
    }

    func testRendersAFreeFormBlockAsABareSentence() throws {
        var p = try sample()
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She hums when she lies.")

        XCTAssertTrue(Markdown.render(p).contains("- She hums when she lies."))
    }

    func testHandlesAProjectWithNothingInIt() {
        let md = Markdown.render(Stories.createProject(title: "Empty"))
        XCTAssertTrue(md.contains("# Empty"))
        XCTAssertTrue(md.contains("_No blocks yet._"))
    }

    func testSlugify() {
        XCTAssertEqual(Markdown.slugify("The Wreck"), "the-wreck")
        XCTAssertEqual(Markdown.slugify("  !!!  "), "writerblocks")
    }
}
