import AppKit
import SwiftUI
import WriterblocksCore

/// The blocks, assembled.
struct OutlineDocumentView: View {
    let project: Project

    @State private var copied = false

    private var outline: Outline { OutlineBuilder.build(project) }
    private var stats: ProjectStats { OutlineBuilder.stats(project) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(copied ? "Copied" : "Copy as Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Markdown.render(project), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copied = false }
                }
                .disabled(stats.blocks == 0)

                Button("Export Markdown…") {
                    NotificationCenter.default.post(name: .exportMarkdown, object: nil)
                }
                .disabled(stats.blocks == 0)

                Spacer()
            }
            .padding(12)

            Divider()

            if outline.isEmpty {
                Spacer()
                Text("No blocks yet. Answer a question or two and the outline builds itself.")
                    .foregroundStyle(.secondary)
                    .italic()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(project.title)
                            .font(.system(size: 30, weight: .semibold, design: .serif))

                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .padding(.bottom, 24)

                        ForEach(outline) { section in
                            Text(section.heading)
                                .font(.system(size: 19, weight: .semibold, design: .serif))
                                .padding(.top, 20)
                                .padding(.bottom, 6)

                            Divider()

                            ForEach(section.groups) { group in
                                if let heading = group.heading {
                                    Text(heading)
                                        .font(.headline)
                                        .foregroundStyle(.tint)
                                        .padding(.top, 14)
                                        .padding(.bottom, 4)
                                }

                                ForEach(group.blocks) { block in
                                    line(block)
                                        .padding(.vertical, 3)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var summary: String {
        let plural = stats.blocks == 1 ? "" : "s"
        return stats.open > 0
            ? "\(stats.blocks) block\(plural), \(stats.open) still open"
            : "\(stats.blocks) block\(plural)"
    }

    @ViewBuilder
    private func line(_ block: Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.tertiary)

            // An outline that hides its holes is a worse outline.
            if block.prompt.isEmpty {
                Text(block.answer)
            } else if block.answer.isEmpty {
                (Text(block.prompt).italic().foregroundColor(.secondary)
                    + Text(" — ")
                    + Text("still open").italic().foregroundColor(.orange))
            } else {
                (Text(block.prompt + " ").italic().foregroundColor(.secondary)
                    + Text(block.answer))
            }

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
