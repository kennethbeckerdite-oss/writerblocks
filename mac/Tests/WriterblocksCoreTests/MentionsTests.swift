import XCTest
@testable import WriterblocksCore

/// Naming someone from inside a sentence. Most of these are about when the
/// menu must *not* appear — a list that pops up over ordinary prose is worse
/// than no list at all.
final class MentionsTests: XCTestCase {

    private func story() -> Project {
        var p = Stories.createProject()
        p = Stories.addStrand(p, type: .character, label: "Marla")
        p = Stories.addStrand(p, type: .character, label: "Howard")
        p = Stories.addStrand(p, type: .setting, label: "The diner")
        return p
    }

    // MARK: - When the menu opens

    func testOpensOnASlashAtTheStartOrAfterASpace() {
        XCTAssertEqual(Mentions.activeToken(in: "/"), "")
        XCTAssertEqual(Mentions.activeToken(in: "/how"), "how")
        XCTAssertEqual(Mentions.activeToken(in: "she still owes /how"), "how")
    }

    func testStaysShutWhenThereIsNoSlash() {
        XCTAssertNil(Mentions.activeToken(in: ""))
        XCTAssertNil(Mentions.activeToken(in: "she still owes him"))
    }

    func testStaysShutInTheMiddleOfAWord() {
        // The ways a slash turns up in ordinary writing.
        XCTAssertNil(Mentions.activeToken(in: "and/or"))
        XCTAssertNil(Mentions.activeToken(in: "open 24/7"))
        XCTAssertNil(Mentions.activeToken(in: "N/A"))
        XCTAssertNil(Mentions.activeToken(in: "http://example"))
    }

    func testTheLastSlashIsTheOneThatCounts() {
        // This is what stops a stray slash from holding the menu open for ever.
        XCTAssertEqual(Mentions.activeToken(in: "/a /b"), "b")
        XCTAssertNil(Mentions.activeToken(in: "/mar/"))
    }

    func testPunctuationClosesIt() {
        // Not "closes when nothing matches" — the row that makes a new
        // character always matches, so the menu would never close on prose.
        XCTAssertNil(Mentions.activeToken(in: "/marla."))
        XCTAssertNil(Mentions.activeToken(in: "/marla, who"))
        XCTAssertNil(Mentions.activeToken(in: "/marla?"))
    }

    func testToleratesANameWithSpacesInIt() {
        XCTAssertEqual(Mentions.activeToken(in: "they met at /the diner"), "the diner")
        XCTAssertEqual(Mentions.activeToken(in: "/marla-jane"), "marla-jane")
        XCTAssertEqual(Mentions.activeToken(in: "/marla's"), "marla's")
    }

    func testGivesUpOnceItIsClearlyProseAgain() {
        XCTAssertNil(Mentions.activeToken(in: "/one two three four five"))
        XCTAssertNil(Mentions.activeToken(in: "/" + String(repeating: "a", count: 41)))
    }

    // MARK: - Who is offered

    func testNeverOffersThePremiseOrTheScenes() {
        // Both are strands, and neither is a subject anyone writes about by name.
        let labels = Mentions.candidates(story(), token: "")
            .flatMap(\.subjects)
            .map(\.label)
        XCTAssertFalse(labels.contains("Premise"))
        XCTAssertFalse(labels.contains("Scenes"))
    }

    func testSegmentsCharactersAndPlaces() throws {
        let groups = Mentions.candidates(story(), token: "")
        XCTAssertEqual(groups.map(\.heading), ["Characters", "Places"])
        XCTAssertEqual(groups[0].subjects.map(\.label), ["Marla", "Howard"])
        XCTAssertEqual(groups[1].subjects.map(\.label), ["The diner"])
    }

    func testPutsMakingSomethingNewFirst() throws {
        let groups = Mentions.candidates(story(), token: "sam")
        let first = try XCTUnwrap(groups.first)
        XCTAssertNil(first.heading)
        XCTAssertEqual(first.subjects.map(\.type), [.character, .setting])
        XCTAssertTrue(first.subjects.allSatisfy(\.isNew))
        XCTAssertEqual(first.subjects.first?.label, "sam")
    }

    func testWillNotMakeSomethingWithNoName() {
        // Otherwise a writer who types "/" and clicks through gets a character
        // called "Untitled", which the matcher throws out as a stopword — one
        // that can never be connected to anything.
        XCTAssertFalse(Mentions.candidates(story(), token: "").contains { $0.heading == nil })
        XCTAssertFalse(Mentions.candidates(story(), token: "   ").contains { $0.heading == nil })
    }

    func testFiltersOnAnyWordOfTheName() {
        XCTAssertTrue(Mentions.matches("Marla Vance", "mar"))
        XCTAssertTrue(Mentions.matches("Marla Vance", "van"))
        XCTAssertTrue(Mentions.matches("The diner", "din"))
        XCTAssertTrue(Mentions.matches("Howard", "HOW"))
        // Prefixes only. Anything looser keeps matching once the writer has
        // gone back to writing.
        XCTAssertFalse(Mentions.matches("Marla", "arl"))
        XCTAssertFalse(Mentions.matches("Marla", "zz"))
    }

    // MARK: - What gets written

    func testWritesTheNameAndOneSpace() throws {
        let marla = try XCTUnwrap(
            Mentions.candidates(story(), token: "mar").flatMap(\.subjects).first { !$0.isNew }
        )
        XCTAssertEqual(Mentions.insert(marla, into: "she still owes /mar"), "she still owes Marla ")
        XCTAssertEqual(Mentions.insert(marla, into: "/mar"), "Marla ")
    }

    func testWritesTheNameOutOfALabelThatIsReallyAnAnswer() throws {
        var p = Stories.createProject()
        let clipped = Stories.labelFromAnswer("Marla Vance, who runs the yard and owes everyone")
        p = Stories.addStrand(p, type: .character, label: clipped)

        let subject = try XCTUnwrap(
            Mentions.candidates(p, token: "mar").flatMap(\.subjects).first { !$0.isNew }
        )
        // The menu shows the whole answer; the sentence gets a name.
        XCTAssertEqual(subject.label, clipped)
        XCTAssertEqual(subject.writes, "Marla")
        XCTAssertEqual(Mentions.insert(subject, into: "she owes /mar"), "she owes Marla ")
    }

    func testLeavesTheDraftAloneWhenThereIsNothingToReplace() throws {
        let marla = try XCTUnwrap(
            Mentions.candidates(story(), token: "mar").flatMap(\.subjects).first { !$0.isNew }
        )
        XCTAssertEqual(Mentions.insert(marla, into: "no slash here"), "no slash here")
        XCTAssertEqual(Mentions.insert(marla, into: "and/or"), "and/or")
    }

    // MARK: - The point of all of it

    func testWhatIsWrittenIsFoundAgain() throws {
        // The feature exists so that a name dropped into a sentence connects
        // two people. This is that claim, checked end to end in the engine.
        var p = story()
        let marla = try XCTUnwrap(p.strands.first { $0.label == "Marla" })
        let howard = try XCTUnwrap(p.strands.first { $0.label == "Howard" })

        let subject = try XCTUnwrap(
            Mentions.candidates(p, token: "how").flatMap(\.subjects).first { !$0.isNew }
        )
        let sentence = Mentions.insert(subject, into: "she still owes /how")
        p = Stories.addFreeBlock(p, strandId: marla.id, answer: sentence)

        let edge = Webs.edges(p).first { edge in
            (edge.a == marla.id && edge.b == howard.id) || (edge.a == howard.id && edge.b == marla.id)
        }
        XCTAssertNotNil(edge, "wrote \"\(sentence)\" and it drew no line")
    }

    func testSaysSoWhenANameCannotBeFoundAgain() throws {
        // The honest half. These labels connect nothing however carefully they
        // are typed, so the menu marks them instead of failing quietly.
        var p = Stories.createProject()
        p = Stories.addStrand(p, type: .character, label: "Jo")
        p = Stories.addStrand(p, type: .character, label: "The Man")
        p = Stories.addStrand(
            p,
            type: .character,
            label: Stories.labelFromAnswer("A retired dockworker who never left the harbour")
        )

        let existing = Mentions.candidates(p, token: "").flatMap(\.subjects).filter { !$0.isNew }
        XCTAssertEqual(existing.count, 3)
        XCTAssertTrue(existing.allSatisfy { !$0.isMatchable })
        // ...and they are still offered, because a writer may well want to type
        // the name anyway.
        XCTAssertTrue(existing.contains { $0.label == "Jo" })
    }
}
