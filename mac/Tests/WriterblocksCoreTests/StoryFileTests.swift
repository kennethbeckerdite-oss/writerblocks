import XCTest
@testable import WriterblocksCore

final class StoryFileTests: XCTestCase {

    // MARK: - Fixtures

    /// A story built by the *web prototype's own engine* and committed as a
    /// fixture, alongside the Markdown that engine produced for it. If the Swift
    /// port ever drifts, this is what catches it.
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "story.writerblocks", withExtension: "json"),
            "fixture missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    private func expectedMarkdown() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "story.expected", withExtension: "md")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func fixtureProject() throws -> Project {
        try StoryFile.decode(try fixtureData())
    }

    // MARK: - Cross-implementation compatibility

    func testOpensAStoryWrittenByTheWebPrototype() throws {
        let project = try fixtureProject()

        XCTAssertEqual(project.title, "The Wreck")
        XCTAssertEqual(project.blocks.count, 11)
        XCTAssertEqual(project.strands.count, 4)
        XCTAssertEqual(project.skipped.count, 1)
    }

    /// The real proof: same story in, same outline out, character for character.
    func testProducesTheSameMarkdownAsTheWebPrototype() throws {
        let project = try fixtureProject()
        XCTAssertEqual(Markdown.render(project), try expectedMarkdown())
    }

    func testSurvivesAFullEncodeDecodeRoundTrip() throws {
        let project = try fixtureProject()
        let reencoded = try StoryFile.encode(project)
        let restored = try StoryFile.decode(reencoded)

        XCTAssertEqual(restored, project)
        XCTAssertEqual(Markdown.render(restored), try expectedMarkdown())
    }

    func testStatsMatchTheFixture() throws {
        let s = OutlineBuilder.stats(try fixtureProject())
        XCTAssertEqual(s.blocks, 11)
        XCTAssertEqual(s.open, 1)
        XCTAssertEqual(s.characters, 1)
        XCTAssertEqual(s.settings, 1)
    }

    // MARK: - Tolerance

    private func fixtureObject() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixtureData()) as? [String: Any]
        )
    }

    func testRejectsThingsThatAreNotStories() {
        XCTAssertNil(StoryFile.parse(nil))
        XCTAssertNil(StoryFile.parse("nope"))
        XCTAssertNil(StoryFile.parse([String: Any]()))
        XCTAssertNil(StoryFile.parse(["strands": [Any](), "blocks": [Any]()]))
        XCTAssertNil(StoryFile.parse(["strands": "x", "blocks": [Any]()]))
    }

    func testDropsMalformedStrandsButKeepsTheGoodOnes() throws {
        var raw = try fixtureObject()
        var strands = try XCTUnwrap(raw["strands"] as? [Any])
        let good = strands.count
        strands.append(["id": "bad", "type": "not-a-type", "label": "x"])
        strands.append("not even an object")
        raw["strands"] = strands

        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.strands.count, good)
    }

    func testDropsBlocksOrphanedByAMissingStrand() throws {
        var raw = try fixtureObject()
        var blocks = try XCTUnwrap(raw["blocks"] as? [Any])
        let good = blocks.count
        blocks.append(["id": "orphan", "strandId": "gone", "answer": "floating"])
        raw["blocks"] = blocks

        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.blocks.count, good)
        XCTAssertFalse(restored.blocks.contains { $0.id == "orphan" })
    }

    func testFillsInMissingFieldsRatherThanRefusingTheFile() throws {
        var raw = try fixtureObject()
        raw.removeValue(forKey: "title")
        raw.removeValue(forKey: "skipped")
        raw.removeValue(forKey: "createdAt")

        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.title, "Untitled story")
        XCTAssertTrue(restored.skipped.isEmpty)
        XCTAssertGreaterThan(restored.createdAt, 0)
    }

    func testKeepsABlockWhoseLinkPointsAtAStrandThatIsGone() throws {
        var raw = try fixtureObject()
        var blocks = try XCTUnwrap(raw["blocks"] as? [Any])
        var first = try XCTUnwrap(blocks[0] as? [String: Any])
        let id = try XCTUnwrap(first["id"] as? String)
        first["aboutStrandId"] = "a strand that is not in this file"
        blocks[0] = first
        raw["blocks"] = blocks

        // The names are already written into the prompt, so the sentence is
        // still worth reading. Only the link is lost.
        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.blocks.count, 11)
        XCTAssertNil(try XCTUnwrap(restored.blocks.first { $0.id == id }).aboutStrandId)
    }

    func testReadsALinkBetweenTwoStrandsAndSurvivesAMalformedOne() throws {
        var raw = try fixtureObject()
        let strandIds = try XCTUnwrap(raw["strands"] as? [Any])
            .compactMap { ($0 as? [String: Any])?["id"] as? String }
        var blocks = try XCTUnwrap(raw["blocks"] as? [Any])

        var good = try XCTUnwrap(blocks[0] as? [String: Any])
        good["aboutStrandId"] = strandIds[1]
        blocks[0] = good

        var bad = try XCTUnwrap(blocks[1] as? [String: Any])
        bad["aboutStrandId"] = 42
        blocks[1] = bad

        raw["blocks"] = blocks

        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.blocks.count, 11)
        XCTAssertEqual(restored.blocks[0].aboutStrandId, strandIds[1])
        XCTAssertNil(restored.blocks[1].aboutStrandId)
    }

    func testIgnoresUnknownFieldsFromANewerBuild() throws {
        var raw = try fixtureObject()
        raw["somethingFromTheFuture"] = ["nested": true]

        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.blocks.count, 11)
    }

    func testSortsStrandsIntoOrderOnTheWayIn() throws {
        var raw = try fixtureObject()
        // Array(...) matters: `.reversed()` alone yields a ReversedCollection,
        // which is not `[Any]`, and parse would reject the whole document.
        raw["strands"] = Array(try XCTUnwrap(raw["strands"] as? [Any]).reversed())

        let restored = try XCTUnwrap(StoryFile.parse(raw))
        XCTAssertEqual(restored.strands.map(\.order), restored.strands.map(\.order).sorted())
    }

    func testABooleanIsNotMistakenForANumber() {
        // NSNumber bridging would happily turn `true` into 1 and silently place
        // a scene at beat 1.
        let raw: [String: Any] = [
            "strands": [["id": "s1", "type": "scene", "label": "Scenes", "order": 0]],
            "blocks": [["id": "b1", "strandId": "s1", "answer": "x", "beat": true]]
        ]
        let restored = StoryFile.parse(raw)
        XCTAssertNil(restored?.blocks.first?.beat)
    }

    /// The mirror of the test above, and the one that actually bit: Foundation
    /// bridges `NSNumber(0)` and `NSNumber(1)` to `Bool` as well as to `Int`, so
    /// a naive "is this a Bool?" guard throws away a legitimate zero. The very
    /// first scene sits at beat 0 and the first block of every strand is at
    /// order 0, so getting this wrong quietly reorders stories.
    func testZeroAndOneAreKeptAsNumbers() throws {
        let raw: [String: Any] = [
            "strands": [["id": "s1", "type": "scene", "label": "Scenes", "order": 0]],
            "blocks": [
                ["id": "b1", "strandId": "s1", "answer": "opening", "beat": 0, "order": 0],
                ["id": "b2", "strandId": "s1", "answer": "next", "beat": 1, "order": 1]
            ]
        ]
        let restored = try XCTUnwrap(StoryFile.parse(raw))

        XCTAssertEqual(restored.blocks.first?.beat, 0)
        XCTAssertEqual(restored.blocks.first?.order, 0)
        XCTAssertEqual(restored.blocks.last?.beat, 1)
        XCTAssertEqual(restored.strands.first?.order, 0)
    }
}
