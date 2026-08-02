import Foundation

public let schemaVersion = 1

public enum StoryFileError: Error, Equatable {
    case notAStory
}

/// Reading and writing `.writerblocks` documents.
///
/// This deliberately mirrors the web prototype's `parseProject` rather than
/// relying on synthesised `Codable` decoding. Synthesised decoding throws on the
/// first missing key and takes the whole document with it; a story file is
/// untrusted input — it may come off disk, out of an older build, or from
/// somebody's Downloads folder — and losing a hundred sentences because one
/// block lacked a field is not an acceptable trade. Anything unreadable is
/// dropped; everything readable is kept.
public enum StoryFile {

    // MARK: - Reading

    public static func decode(_ data: Data) throws -> Project {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw StoryFileError.notAStory
        }
        guard let project = parse(root) else { throw StoryFileError.notAStory }
        return project
    }

    /// Rebuild a project from an already-parsed JSON value.
    public static func parse(_ value: Any?) -> Project? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let rawStrands = dict["strands"] as? [Any],
              let rawBlocks = dict["blocks"] as? [Any]
        else { return nil }

        let strands = rawStrands.enumerated().compactMap { parseStrand($0.element, index: $0.offset) }
        // A story with no readable strand has nothing to hang blocks on.
        if strands.isEmpty { return nil }

        let strandIds = Set(strands.map(\.id))
        let blocks = rawBlocks.enumerated().compactMap {
            parseBlock($0.element, index: $0.offset, strandIds: strandIds)
        }

        let now = Date().timeIntervalSince1970 * 1000
        return Project(
            id: nonEmpty(dict["id"]) ?? UUID().uuidString,
            title: string(dict["title"], "Untitled story"),
            schemaVersion: schemaVersion,
            strands: strands.sorted { $0.order < $1.order },
            blocks: blocks,
            skipped: parseSkipped(dict["skipped"]),
            createdAt: double(dict["createdAt"], now),
            updatedAt: double(dict["updatedAt"], now)
        )
    }

    private static func parseStrand(_ value: Any?, index: Int) -> Strand? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let id = nonEmpty(dict["id"]) else { return nil }
        guard let rawType = dict["type"] as? String,
              let type = StrandType(rawValue: rawType)
        else { return nil }

        return Strand(
            id: id,
            type: type,
            label: string(dict["label"], "Untitled"),
            order: int(dict["order"], index),
            createdAt: double(dict["createdAt"], Date().timeIntervalSince1970 * 1000)
        )
    }

    private static func parseBlock(_ value: Any?, index: Int, strandIds: Set<String>) -> Block? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let id = nonEmpty(dict["id"]) else { return nil }
        // A block whose strand is gone has nowhere to live.
        guard let strandId = nonEmpty(dict["strandId"]), strandIds.contains(strandId) else {
            return nil
        }

        return Block(
            id: id,
            strandId: strandId,
            questionId: dict["questionId"] as? String,
            prompt: string(dict["prompt"], ""),
            answer: string(dict["answer"], ""),
            beat: optionalInt(dict["beat"]),
            order: int(dict["order"], index),
            createdAt: double(dict["createdAt"], Date().timeIntervalSince1970 * 1000)
        )
    }

    private static func parseSkipped(_ value: Any?) -> [String: Int] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (key, raw) in dict {
            if let at = optionalInt(raw) { out[key] = at }
        }
        return out
    }

    // MARK: - Writing

    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        // Stable key order keeps diffs readable when a story is kept in git.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    // MARK: - Coercion helpers

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func string(_ value: Any?, _ fallback: String) -> String {
        value as? String ?? fallback
    }

    /// `value is Bool` is not usable here: Foundation bridges `NSNumber(0)` and
    /// `NSNumber(1)` to `Bool` as well as to `Int`, so testing for Bool that way
    /// would reject a perfectly good `beat: 0` or `order: 0`. JSONSerialization
    /// represents a real JSON boolean as `CFBoolean`, which is distinguishable.
    private static func isBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID()
    }

    private static func double(_ value: Any?, _ fallback: Double) -> Double {
        guard let value, !isBoolean(value),
              let n = value as? NSNumber, n.doubleValue.isFinite
        else { return fallback }
        return n.doubleValue
    }

    private static func int(_ value: Any?, _ fallback: Int) -> Int {
        optionalInt(value) ?? fallback
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        guard let value, !isBoolean(value),
              let n = value as? NSNumber, n.doubleValue.isFinite
        else { return nil }
        return n.intValue
    }
}
