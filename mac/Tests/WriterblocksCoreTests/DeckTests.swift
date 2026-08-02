import XCTest
@testable import WriterblocksCore

final class DeckTests: XCTestCase {

    // MARK: - Helpers

    private func strand(_ project: Project, ofType type: StrandType) throws -> Strand {
        try XCTUnwrap(project.strands.first { $0.type == type }, "no \(type) strand")
    }

    private func question(_ id: String) throws -> QuestionTemplate {
        try XCTUnwrap(Questions.question(id), "no question \(id)")
    }

    /// Answer whatever is on top of the deck, `times` times.
    private func answerMany(_ project: Project, _ times: Int, answer: String = "something") -> Project {
        var p = project
        for _ in 0..<times {
            guard let dealt = Deck.nextQuestion(p) else { break }
            p = Stories.applyAnswer(p, dealt, answer)
        }
        return p
    }

    /// Every question the deck will currently offer for one strand, found by
    /// skipping rather than answering so the gating stays fixed while we look.
    private func offered(_ project: Project, for strandId: String) -> Set<String> {
        var ids = Set<String>()
        var probe = project
        while true {
            guard let dealt = Deck.nextQuestion(probe, focusStrandId: strandId),
                  dealt.strand.id == strandId,
                  !ids.contains(dealt.template.id)
            else { break }
            ids.insert(dealt.template.id)
            probe = Stories.skipQuestion(probe, strandId: strandId, questionId: dealt.template.id)
        }
        return ids
    }

    private func started() throws -> Project {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A logline.")
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "Marla")
        return p
    }

    // MARK: - Tests

    func testOpensWithTheLogline() {
        XCTAssertEqual(Deck.nextQuestion(Stories.createProject())?.template.id, "logline")
    }

    func testAsksWhoTheMainCharacterIsOnceTheLoglineIsDown() throws {
        var p = Stories.createProject()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A diver goes back for the wreck.")
        XCTAssertEqual(Deck.nextQuestion(p)?.template.id, "main-character")
    }

    func testSubstitutesTheSubjectIntoTheQuestionText() throws {
        var p = try started()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A harbour town")

        let dealt = try XCTUnwrap(Deck.nextQuestion(p))
        XCTAssertFalse(dealt.text.contains("{subject}"))
        XCTAssertTrue(
            dealt.text.contains("Marla") || dealt.text.contains("A harbour town"),
            "expected a named subject, got: \(dealt.text)"
        )
    }

    func testNeverAsksTheSameOneOffQuestionTwiceForTheSameStrand() {
        var p = Stories.createProject()
        var seen = Set<String>()
        for i in 0..<60 {
            guard let dealt = Deck.nextQuestion(p) else { break }
            if !dealt.template.isRepeatable {
                let key = Deck.skipKey(dealt.strand.id, dealt.template.id)
                XCTAssertFalse(seen.contains(key), "asked \(key) twice")
                seen.insert(key)
            }
            p = Stories.applyAnswer(p, dealt, "answer \(i)")
        }
    }

    func testKeepsAGatedQuestionOutOfReachUntilItsParentIsAnswered() throws {
        var p = try started()
        let marla = try strand(p, ofType: .character)

        XCTAssertFalse(offered(p, for: marla.id).contains("char-likes-job"))

        p = Stories.applyAnswer(
            p,
            DealtQuestion(template: try question("char-vocation"), strand: marla, text: "Job?"),
            "She dives."
        )

        XCTAssertTrue(offered(p, for: marla.id).contains("char-likes-job"))
    }

    func testDoesNotUnlockAFollowUpOnAnEmptyNotSureYetAnswer() throws {
        var p = try started()
        let marla = try strand(p, ofType: .character)

        p = Stories.applyAnswer(
            p,
            DealtQuestion(template: try question("char-vocation"), strand: marla, text: "Job?"),
            "   "
        )

        let ids = offered(p, for: marla.id)
        XCTAssertFalse(ids.contains("char-likes-job"))
        // ...and the question itself is spent, not re-asked.
        XCTAssertFalse(ids.contains("char-vocation"))
    }

    func testSendsASkippedQuestionToTheBackRatherThanThrowingItAway() throws {
        let p = Stories.createProject()
        let first = try XCTUnwrap(Deck.nextQuestion(p))
        let skipped = Stories.skipQuestion(p, strandId: first.strand.id, questionId: first.template.id)

        XCTAssertNotEqual(Deck.nextQuestion(skipped)?.template.id, first.template.id)
        // Still in the deck, just further down it.
        XCTAssertEqual(Deck.remainingCount(skipped), Deck.remainingCount(p))
        XCTAssertTrue(offered(skipped, for: first.strand.id).contains(first.template.id))
    }

    /// The UI promises nothing is ever lost. Answering keeps spawning new
    /// subjects with fresh questions, so a skip that sorted behind *everything*
    /// would in practice mean "never again".
    func testActuallyBringsASkippedQuestionBackWhileTheWriterIsStillWorking() throws {
        var p = Stories.createProject()
        let first = try XCTUnwrap(Deck.nextQuestion(p))
        p = Stories.skipQuestion(p, strandId: first.strand.id, questionId: first.template.id)

        var returnedAfter = -1
        for i in 0..<40 {
            guard let dealt = Deck.nextQuestion(p) else { break }
            if dealt.template.id == first.template.id && dealt.strand.id == first.strand.id {
                returnedAfter = i
                break
            }
            p = Stories.applyAnswer(p, dealt, "answer \(i)")
        }

        XCTAssertGreaterThan(returnedAfter, 0, "a skipped question never came back")
        XCTAssertLessThan(returnedAfter, 40)
    }

    func testScopesASkipToASingleStrand() throws {
        var p = try started()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A harbour town")
        p = Stories.applyAnswer(
            p,
            DealtQuestion(
                template: try question("another-character"),
                strand: try strand(p, ofType: .premise),
                text: "Who else?"
            ),
            "Jim"
        )

        let characters = p.strands.filter { $0.type == .character }
        XCTAssertEqual(characters.count, 2)
        let marla = try XCTUnwrap(characters.first)
        let jim = try XCTUnwrap(characters.last)

        p = Stories.skipQuestion(p, strandId: marla.id, questionId: "char-like")

        XCTAssertEqual(Array(p.skipped.keys), [Deck.skipKey(marla.id, "char-like")])
        // Jim is untouched by Marla's skip.
        XCTAssertEqual(Deck.nextQuestion(p, focusStrandId: jim.id)?.template.id, "char-like")
        XCTAssertNotEqual(Deck.nextQuestion(p, focusStrandId: marla.id)?.template.id, "char-like")
    }

    func testSpreadsQuestionsAcrossCharactersInsteadOfBurrowingIntoOne() throws {
        var p = try started()
        p = Stories.applyAnswer(p, try XCTUnwrap(Deck.nextQuestion(p)), "A harbour town")
        p = Stories.applyAnswer(
            p,
            DealtQuestion(
                template: try question("another-character"),
                strand: try strand(p, ofType: .premise),
                text: "Who else?"
            ),
            "Jim"
        )

        let characters = p.strands.filter { $0.type == .character }
        var hits: [String: Int] = [:]
        var probe = p
        for _ in 0..<10 {
            guard let dealt = Deck.nextQuestion(probe) else { break }
            hits[dealt.strand.id, default: 0] += 1
            probe = Stories.applyAnswer(probe, dealt, "x")
        }

        for character in characters {
            XCTAssertGreaterThan(hits[character.id] ?? 0, 0, "\(character.label) never got asked")
        }
    }

    func testHonoursAFocusStrandThenFallsBackOnceItRunsDry() throws {
        var p = try started()
        let marla = try strand(p, ofType: .character)

        for _ in 0..<5 {
            let dealt = try XCTUnwrap(Deck.nextQuestion(p, focusStrandId: marla.id))
            XCTAssertEqual(dealt.strand.id, marla.id)
            p = Stories.applyAnswer(p, dealt, "x")
        }

        // Drain Marla entirely; focus must fall back rather than dead-end.
        for _ in 0..<100 {
            guard let dealt = Deck.nextQuestion(p, focusStrandId: marla.id),
                  dealt.strand.id == marla.id
            else { break }
            p = Stories.applyAnswer(p, dealt, "x")
        }

        let after = Deck.nextQuestion(p, focusStrandId: marla.id)
        XCTAssertNotNil(after)
        XCTAssertNotEqual(after?.strand.id, marla.id)
    }

    func testNeverRunsOutHoweverLongTheWriterKeepsGoing() {
        // This is the point of the tool: the writer is never told there is
        // nothing more to say.
        let p = answerMany(Stories.createProject(), 300)
        XCTAssertEqual(p.blocks.count, 300)
        XCTAssertNotNil(Deck.nextQuestion(p))
        XCTAssertGreaterThan(Deck.remainingCount(p), 0)
    }

    func testKeepsTheOpenEndedQuestionsAvailableForever() throws {
        var p = Stories.createProject()
        let premise = try strand(p, ofType: .premise)
        for _ in 0..<40 {
            guard let dealt = Deck.nextQuestion(p, focusStrandId: premise.id),
                  dealt.strand.id == premise.id
            else { break }
            // Answer blank so nothing new spawns and the premise strand stays alone.
            p = Stories.applyAnswer(p, dealt, "")
        }

        let ids = offered(p, for: premise.id)
        XCTAssertTrue(ids.contains("another-character"))
        XCTAssertTrue(ids.contains("another-place"))
        XCTAssertFalse(ids.contains("logline"))
    }

    func testReturnsNilOnlyWhenThereIsNothingToAskAboutAtAll() {
        var empty = Stories.createProject()
        empty.strands = []
        XCTAssertNil(Deck.nextQuestion(empty))
        XCTAssertEqual(Deck.remainingCount(empty), 0)
    }

    func testStaysFastAsTheProjectGrows() {
        let p = answerMany(Stories.createProject(), 300)
        let started = Date()
        for _ in 0..<50 { _ = Deck.nextQuestion(p) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
    }
}
