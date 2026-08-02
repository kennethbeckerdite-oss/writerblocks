import Foundation

/// The deck, loaded from `questions.json`.
///
/// The JSON is content, not machinery — rewrite it freely. The rules it has to
/// obey are small:
///
///  - Every question must be answerable in one sentence. If a question needs a
///    paragraph, it is too big and belongs split in two.
///  - Questions are concrete. "What is the theme?" is a question that produces
///    block; "what does this person do when no one is watching?" is a question
///    that produces a sentence.
///  - `priority` orders the asking (lower first). Ties break toward the strand
///    with the fewest blocks, so the web grows outward rather than down.
///  - `unlocks` gates a follow-up behind its parent, so we never ask "would they
///    rather be doing something else?" before we know what their job is.
///  - `beat` places a scene in story chronology so the outline reads in order
///    even when the writer answers the ending first.
public enum Questions {

    public static let all: [QuestionTemplate] = loadDeck()

    private static let byId: [String: QuestionTemplate] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func question(_ id: String) -> QuestionTemplate? { byId[id] }

    /// Every question id that appears in some other question's `unlocks`. These
    /// are not askable until one of their parents has been answered.
    public static let gatedIds: Set<String> = Set(all.flatMap { $0.unlocks ?? [] })

    private static let parents: [String: [String]] = {
        var map: [String: [String]] = [:]
        for q in all {
            for childId in q.unlocks ?? [] {
                map[childId, default: []].append(q.id)
            }
        }
        return map
    }()

    /// The questions that, once answered, open `childId`.
    public static func parentsOf(_ childId: String) -> [String] {
        parents[childId] ?? []
    }

    private static func loadDeck() -> [QuestionTemplate] {
        guard let url = Bundle.module.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            // The deck is bundled with the library; if it is missing the build
            // is broken in a way no fallback can paper over.
            preconditionFailure("questions.json is missing from the bundle")
        }

        do {
            return try JSONDecoder().decode([QuestionTemplate].self, from: data)
        } catch {
            preconditionFailure("questions.json could not be decoded: \(error)")
        }
    }
}
