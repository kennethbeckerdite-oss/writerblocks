import XCTest
@testable import WriterblocksCore

/// Connections between characters are derived from the sentences, never stored.
/// These are the rules that derivation has to obey — mostly about what must
/// *not* count as a mention, because a graph full of edges nobody meant is
/// worse than no graph at all.
final class WebsTests: XCTestCase {

    // MARK: - Helpers

    private func project(characters: [String]) -> Project {
        var p = Stories.createProject()
        for name in characters { p = Stories.addStrand(p, type: .character, label: name) }
        return p
    }

    private func strand(_ p: Project, _ label: String) throws -> Strand {
        try XCTUnwrap(p.strands.first { $0.label == label })
    }

    private func edge(_ p: Project, _ x: Strand, _ y: Strand) -> WebEdge? {
        Webs.edges(p).first { ($0.a == x.id && $0.b == y.id) || ($0.a == y.id && $0.b == x.id) }
    }

    private func matches(_ label: String, in answer: String) -> Bool {
        guard let needle = Webs.needle(for: label) else { return false }
        return Webs.mentions(Array(answer.lowercased().utf8), needle)
    }

    // MARK: - Matching

    func testFindsANameRegardlessOfCase() {
        XCTAssertTrue(matches("Howard", in: "she never trusted HOWARD"))
        XCTAssertTrue(matches("howard", in: "Howard again"))
    }

    func testOnlyMatchesWholeWords() {
        // The failure this exists to prevent: "Ana" inside "banana" would put an
        // edge in very nearly every story.
        XCTAssertFalse(matches("Ana", in: "she ate a banana"))
        XCTAssertFalse(matches("Jo", in: "he needed the job"))
        XCTAssertFalse(matches("Howard", in: "Howards End"))
        XCTAssertTrue(matches("Ana", in: "Ana left"))
    }

    func testDoesNotMatchAcrossAMultiByteCharacter() {
        // Every continuation byte of a multi-byte character counts as part of
        // the word, so the boundary comes out right without decoding anything.
        XCTAssertFalse(matches("Ana", in: "Anaïs said nothing"))
        XCTAssertTrue(matches("Anaïs", in: "Anaïs said nothing"))
    }

    func testMatchesThroughAPossessive() {
        XCTAssertTrue(matches("Marla", in: "she took Marla's coat"))
    }

    func testIgnoresLabelsThatWouldMatchEverything() {
        XCTAssertNil(Webs.needle(for: "the"))
        XCTAssertNil(Webs.needle(for: "The Man"))
        XCTAssertNil(Webs.needle(for: "Untitled"))
        // Two letters is not a name worth hunting for.
        XCTAssertNil(Webs.needle(for: "Jo"))
    }

    func testMatchesAClippedDescriptionOnItsFirstNameOnly() throws {
        // labelFromAnswer clips at 40 characters, so a character described
        // rather than named arrives here as a sentence fragment.
        let described = Stories.labelFromAnswer("A retired dockworker who never left the harbour")
        XCTAssertNil(Webs.needle(for: described), "a description must not be hunted for")

        let named = Stories.labelFromAnswer("Marla Vance, who runs the yard and owes everyone")
        XCTAssertTrue(matches(named, in: "Marla came back"))
        XCTAssertFalse(matches(named, in: "the yard was empty"))
    }

    // MARK: - Edges

    func testConnectsTwoCharactersWhenOneIsNamedInTheOthersAnswer() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        let howard = try strand(p, "Howard")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She still owes Howard money.")

        let found = try XCTUnwrap(edge(p, marla, howard))
        XCTAssertEqual(found.mentions, 1)
        XCTAssertEqual(found.pairBlocks, 0)
        XCTAssertFalse(found.isAnswered)
    }

    func testConnectsTwoCharactersNamedInTheSameSentenceAnywhere() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        let howard = try strand(p, "Howard")
        let premise = try XCTUnwrap(p.strands.first { $0.type == .premise })
        p = Stories.addFreeBlock(p, strandId: premise.id, answer: "Marla and Howard were partners once.")

        XCTAssertNotNil(edge(p, marla, howard), "a sentence naming both connects them wherever it lives")
    }

    func testDoesNotConnectACharacterToThemselves() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "Marla never says what she means.")

        XCTAssertTrue(Webs.edges(p).isEmpty)
    }

    func testNeverReadsThePromptOnlyTheAnswer() throws {
        // Every prompt names its own subject, and a pair prompt names both. If
        // prompts counted, every block would prove its own link.
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        p = Stories.applyAnswer(
            p,
            DealtQuestion(
                template: try XCTUnwrap(Questions.question("char-like")),
                strand: marla,
                text: "What does Marla think of Howard?"
            ),
            "Nothing she would say out loud."
        )

        XCTAssertTrue(Webs.edges(p).isEmpty)
    }

    func testCountsABlockAskedAboutBothOfThem() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        let howard = try strand(p, "Howard")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "")
        p.blocks[0].aboutStrandId = howard.id

        let found = try XCTUnwrap(edge(p, marla, howard))
        XCTAssertEqual(found.pairBlocks, 1)
        XCTAssertTrue(found.isAnswered, "an unanswered pair block is still a link the writer drew")
    }

    func testKeepsOneEdgePerPairHoweverItWasFound() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        let howard = try strand(p, "Howard")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She still owes Howard.")
        p = Stories.addFreeBlock(p, strandId: howard.id, answer: "Marla took the boat.")

        XCTAssertEqual(Webs.edges(p).count, 1)
        XCTAssertEqual(try XCTUnwrap(edge(p, marla, howard)).mentions, 2)
    }

    func testTakesTheLongerNameWhenOneContainsTheOther() throws {
        var p = project(characters: ["Marla", "Marla Vance", "Howard"])
        let marla = try strand(p, "Marla")
        let vance = try strand(p, "Marla Vance")
        let howard = try strand(p, "Howard")
        p = Stories.addFreeBlock(p, strandId: howard.id, answer: "Marla Vance signed for it.")

        XCTAssertNotNil(edge(p, howard, vance))
        XCTAssertNil(edge(p, howard, marla), "the short name is an artefact of the long one here")
    }

    func testReformsTheWebWhenACharacterIsRenamed() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        let howard = try strand(p, "Howard")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She still owes Delia money.")
        XCTAssertTrue(Webs.edges(p).isEmpty)

        // Nothing is stored, so correcting the name is all it takes.
        p = Stories.renameStrand(p, strandId: howard.id, label: "Delia")
        XCTAssertNotNil(edge(p, marla, try strand(p, "Delia")))
    }

    // MARK: - Opening

    func testStaysShutUntilThereIsSomethingToLookAt() throws {
        var p = project(characters: ["Marla"])
        let marla = try strand(p, "Marla")
        for i in 0..<Webs.minBlocks {
            p = Stories.addFreeBlock(p, strandId: marla.id, answer: "block \(i)")
        }
        XCTAssertFalse(Webs.isOpen(p), "one character is not a web")

        p = Stories.addStrand(p, type: .character, label: "Howard")
        XCTAssertTrue(Webs.isOpen(p))
    }

    func testStaysShutWhileTheStoryIsStillThin() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "Howard again.")
        XCTAssertFalse(Webs.isOpen(p), "two names in the first minute are not yet a cast")
        XCTAssertTrue(Webs.orderedPairs(p).isEmpty, "and there is nothing to ask about them yet")

        for i in 0..<Webs.minBlocks {
            p = Stories.addFreeBlock(p, strandId: marla.id, answer: "block \(i)")
        }
        XCTAssertTrue(Webs.isOpen(p))
    }

    func testAsksAboutAPairFromBothSides() throws {
        var p = project(characters: ["Marla", "Howard"])
        let marla = try strand(p, "Marla")
        let howard = try strand(p, "Howard")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: "She still owes Howard money.")
        for i in 0..<Webs.minBlocks {
            p = Stories.addFreeBlock(p, strandId: marla.id, answer: "block \(i)")
        }

        let pairs = Webs.orderedPairs(p)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertTrue(pairs.contains { $0.subject == marla.id && $0.about == howard.id })
        XCTAssertTrue(pairs.contains { $0.subject == howard.id && $0.about == marla.id })
    }
}
