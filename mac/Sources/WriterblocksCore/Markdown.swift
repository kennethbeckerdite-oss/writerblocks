import Foundation

public enum Markdown {

    private static func line(_ block: Block) -> String {
        let answer = block.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        // A free-form block is just the writer's sentence.
        if block.prompt.isEmpty {
            return answer.isEmpty ? "- _(empty)_" : "- \(answer)"
        }
        // Open threads stay visible. An outline that hides its holes is a worse
        // outline.
        if answer.isEmpty {
            return "- _\(block.prompt)_ — **still open**"
        }
        return "- _\(block.prompt)_ \(answer)"
    }

    /// The blocks, assembled. Deliberately plain Markdown so it pastes cleanly
    /// into Scrivener, Word, Docs, or a plain text file.
    public static func render(_ project: Project) -> String {
        let outline = OutlineBuilder.build(project)
        let s = OutlineBuilder.stats(project)
        var out: [String] = ["# \(project.title)", ""]

        let summary: String
        if s.blocks == 0 {
            summary = "_No blocks yet._"
        } else {
            let plural = s.blocks == 1 ? "" : "s"
            let open = s.open > 0 ? ", \(s.open) still open" : ""
            summary = "_\(s.blocks) block\(plural)\(open)._"
        }
        out.append(summary)
        out.append("")

        for section in outline {
            out.append("## \(section.heading)")
            out.append("")
            for group in section.groups {
                if let heading = group.heading {
                    out.append("### \(heading)")
                    out.append("")
                }
                for block in group.blocks { out.append(line(block)) }
                out.append("")
            }
        }

        // Collapse the trailing blank line into a single terminating newline.
        let joined = out.joined(separator: "\n")
        let trimmed = joined.replacingOccurrences(
            of: "\\s+$", with: "", options: .regularExpression
        )
        return trimmed + "\n"
    }

    public static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        let replaced = lowered.replacingOccurrences(
            of: "[^a-z0-9]+", with: "-", options: .regularExpression
        )
        let slug = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "writerblocks" : slug
    }
}
