import XCTest
@testable import WriterblocksCore

/// The deck is meant to be rewritten by whoever is using the tool. These are
/// the rules an edited deck still has to obey, so a bad edit fails here rather
/// than halfway through someone's writing session.
final class QuestionsTests: XCTestCase {

    func testDeckLoadsFromBundle() {
        XCTAssertEqual(Questions.all.count, 69)
    }

    func testEveryOptionalFieldSurvivedTheJSONRoundTrip() {
        // If these come back empty the JSON export silently dropped fields and
        // the whole deck would behave differently.
        XCTAssertEqual(Questions.all.filter { $0.spawns != nil }.count, 4)
        XCTAssertEqual(Questions.all.filter { $0.unlocks != nil }.count, 5)
        XCTAssertEqual(Questions.all.filter { $0.beat != nil }.count, 13)
        XCTAssertEqual(Questions.all.filter { $0.isRepeatable }.count, 3)
        XCTAssertEqual(Questions.all.filter { $0.hint != nil }.count, 8)
        XCTAssertEqual(Questions.all.filter { $0.titles == true }.count, 1)
        XCTAssertEqual(Questions.all.filter(\.isPair).count, 6)
    }

    func testSomethingNamesTheStory() {
        // Without one of these a story keeps the provisional name cut from its
        // logline for ever, and there is no other way to rename one.
        let namers = Questions.all.filter { $0.titles == true }
        XCTAssertFalse(namers.isEmpty, "no question names the story")
        for q in namers {
            XCTAssertEqual(q.strandType, .premise, "\(q.id) names the story but is not on the premise")
            XCTAssertFalse(q.isRepeatable, "\(q.id) would rename the story over and over")
            XCTAssertNil(q.spawns, "\(q.id) both names the story and spawns a strand")
        }
    }

    func testTheOnlyPlaceholdersAreSubjectAndOther() throws {
        // A typo like {Subject} is not substituted, and question text is stored
        // on the block — so it ships verbatim into someone's exported outline
        // with nothing else in the way to catch it.
        let placeholder = try NSRegularExpression(pattern: "\\{[^}]*\\}")
        for q in Questions.all {
            let range = NSRange(q.text.startIndex..., in: q.text)
            for match in placeholder.matches(in: q.text, range: range) {
                let found = String(q.text[Range(match.range, in: q.text)!])
                XCTAssertTrue(
                    found == "{subject}" || found == "{other}",
                    "\(q.id) has an unknown placeholder \(found)"
                )
            }
        }
    }

    func testTheSecondPersonIsOnlyNamedByAQuestionAboutTwoPeople() {
        for q in Questions.all where q.text.contains("{other}") {
            XCTAssertTrue(q.isPair, "\(q.id) names a second person but is not a pair question")
        }
        for q in Questions.all where q.isPair {
            XCTAssertTrue(q.text.contains("{subject}"), "\(q.id) never names its subject")
            XCTAssertTrue(q.text.contains("{other}"), "\(q.id) never names the other person")
        }
    }

    func testPairQuestionsStayWithinWhatTheDeckCanDealThem() {
        for q in Questions.all where q.isPair {
            // Pairs are found among characters; there is nothing to pair a
            // premise or a scene with.
            XCTAssertEqual(q.strandType, .character, "\(q.id) pairs but is not a character question")
            // The deck offers every pair template for every connected pair, so
            // a repeatable one would never run dry and the focus picker would
            // never fall back.
            XCTAssertFalse(q.isRepeatable, "\(q.id) would never be exhausted")
            XCTAssertNil(q.spawns, "\(q.id) would spawn a strand from an answer about two people")
            XCTAssertNil(q.beat, "\(q.id) is not a scene")
            // Gating keys on one strand and one question. Keeping pairs out of
            // it means there is no second gating path to get wrong.
            XCTAssertNil(q.unlocks, "\(q.id) gates a follow-up")
            XCTAssertFalse(Questions.gatedIds.contains(q.id), "\(q.id) is gated behind another question")
        }
    }

    func testPairQuestionsAreShortEnoughToCarryTwoNames() {
        // A rendered pair question can carry two 40-character labels, which
        // makes it the longest line the outline will ever print.
        for q in Questions.all where q.isPair {
            XCTAssertLessThan(q.text.count, 40, "\(q.id) is too long once two names are in it")
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(Questions.all.map(\.id)).count, Questions.all.count)
    }

    func testTheDeckOpensWithTheLogline() {
        XCTAssertEqual(Questions.all.min { $0.priority < $1.priority }?.id, "logline")
    }

    func testOnlyUnlocksQuestionsThatExist() {
        for q in Questions.all {
            for childId in q.unlocks ?? [] {
                XCTAssertNotNil(Questions.question(childId), "\(q.id) unlocks missing \(childId)")
            }
        }
    }

    func testUnlocksStayWithinTheSameStrandType() {
        // A parent on another strand type could never be answered for this
        // strand, so the child would be unreachable forever.
        for q in Questions.all {
            for childId in q.unlocks ?? [] {
                XCTAssertEqual(Questions.question(childId)?.strandType, q.strandType, "\(q.id) -> \(childId)")
            }
        }
    }

    func testEveryGatedQuestionHasAFindableParent() {
        for id in Questions.gatedIds {
            XCTAssertFalse(Questions.parentsOf(id).isEmpty, "\(id) has no parent")
        }
    }

    func testNoQuestionGatesItself() {
        for q in Questions.all {
            XCTAssertFalse(q.unlocks?.contains(q.id) ?? false, "\(q.id) gates itself")
        }
    }

    func testSubjectPlaceholderOnlyWhereTheStrandHasARealName() {
        // Premise and scene strands are named "Premise" and "Scenes";
        // substituting those into a question produces nonsense.
        for q in Questions.all where q.strandType == .premise || q.strandType == .scene {
            XCTAssertFalse(q.text.contains("{subject}"), "\(q.id) substitutes a generic strand name")
        }
    }

    func testCharacterQuestionsNameTheirCharacter() {
        // A gated follow-up is exempt: "what's standing in the way of that?" is
        // asked right after its parent, which already named who we mean.
        for q in Questions.all where q.strandType == .character && !Questions.gatedIds.contains(q.id) {
            XCTAssertTrue(q.text.contains("{subject}"), "\(q.id) never names its character")
        }
    }

    func testBeatsOnlyOnSceneQuestions() {
        for q in Questions.all where q.beat != nil {
            XCTAssertEqual(q.strandType, .scene, "\(q.id) has a beat but is not a scene")
        }
    }

    func testSpawnsOnlyFromThePremise() {
        for q in Questions.all where q.spawns != nil {
            XCTAssertEqual(q.strandType, .premise, "\(q.id) spawns but is not on the premise")
        }
    }

    func testCoachingLivesInTheHintNotTheQuestion() {
        // The question text is stored on the block and read back in the
        // outline; a long compound question makes for a bad outline line.
        for q in Questions.all {
            XCTAssertLessThan(q.text.count, 70, "\(q.id) is too long to read back in an outline")
            if let hint = q.hint {
                XCTAssertFalse(q.text.contains(hint), "\(q.id) repeats its hint in the question")
            }
        }
    }

    func testEverySectionAsksSomething() {
        for type in StrandType.allCases {
            XCTAssertGreaterThan(Questions.all.filter { $0.strandType == type }.count, 3, "\(type)")
        }
    }
}
