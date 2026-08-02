import SwiftUI
import WriterblocksCore

/// Every block as a card, grouped in columns. Drag to reorder, drag between
/// columns; a block's column decides where it lands in the outline.
struct BoardView: View {
    @Binding var project: Project

    @State private var newStrandType: StrandType = .character
    @State private var newStrandLabel = ""

    private var strands: [Strand] {
        project.strands.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(spacing: 0) {
            addBar
            Divider()

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(strands) { strand in
                        StrandColumnView(project: $project, strand: strand)
                    }
                }
                .padding(16)
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $newStrandType) {
                Text("Character").tag(StrandType.character)
                Text("Place").tag(StrandType.setting)
                Text("Scenes").tag(StrandType.scene)
            }
            .labelsHidden()
            .frame(width: 130)

            TextField("Name it…", text: $newStrandLabel)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(addStrand)

            Button("Add", action: addStrand)
                .disabled(newStrandLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(12)
    }

    private func addStrand() {
        let label = newStrandLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        project = Stories.addStrand(project, type: newStrandType, label: label)
        newStrandLabel = ""
    }
}

private struct StrandColumnView: View {
    @Binding var project: Project
    let strand: Strand

    @State private var renaming = false
    @State private var draftLabel = ""
    @State private var newBlock = ""
    @State private var targeted = false

    private var blocks: [Block] {
        project.blocks.filter { $0.strandId == strand.id }.sorted { $0.order < $1.order }
    }

    private var typeLabel: String {
        switch strand.type {
        case .premise: return "PREMISE"
        case .character: return "CHARACTER"
        case .setting: return "PLACE"
        case .scene: return "SCENES"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(blocks) { block in
                        BlockCardView(project: $project, block: block)
                            .draggable(block.id)
                            .dropDestination(for: String.self) { ids, _ in
                                move(ids, before: block)
                            }
                    }

                    if blocks.isEmpty {
                        Text("Nothing here yet.")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 460)
            // Dropping on the column's empty space appends to the end.
            .dropDestination(for: String.self) { ids, _ in
                move(ids, toIndex: blocks.count)
            } isTargeted: { targeted = $0 }

            Divider()
            TextField("Add a block…", text: $newBlock)
                .textFieldStyle(.plain)
                .padding(8)
                .onSubmit {
                    let text = newBlock.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    project = Stories.addFreeBlock(project, strandId: strand.id, answer: text)
                    newBlock = ""
                }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(targeted ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    TextField("Name", text: $draftLabel)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .onSubmit {
                            project = Stories.renameStrand(
                                project, strandId: strand.id, label: draftLabel
                            )
                            renaming = false
                        }
                } else {
                    Text(strand.label)
                        .font(.headline)
                        .lineLimit(1)
                        .help("\(strand.label) — click to rename")
                        .onTapGesture {
                            draftLabel = strand.label
                            renaming = true
                        }
                }

                Text(typeLabel)
                    .font(.caption2)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if strand.type == .character || strand.type == .setting {
                Button {
                    project = Stories.deleteStrand(project, strandId: strand.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete \(strand.label) and its blocks")
            }
        }
        .padding(10)
    }

    private func move(_ ids: [String], toIndex index: Int) -> Bool {
        guard let blockId = ids.first else { return false }
        project = Stories.moveBlock(
            project, blockId: blockId, toStrandId: strand.id, toIndex: index
        )
        return true
    }

    private func move(_ ids: [String], before block: Block) -> Bool {
        guard let blockId = ids.first, blockId != block.id else { return false }
        let index = blocks.filter { $0.id != blockId }.firstIndex { $0.id == block.id } ?? blocks.count
        return move([blockId], toIndex: index)
    }
}

private struct BlockCardView: View {
    @Binding var project: Project
    let block: Block

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !block.prompt.isEmpty {
                Text(block.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if editing {
                TextField("One sentence…", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(commit)
            } else if block.answer.isEmpty {
                Text("still open")
                    .italic()
                    .foregroundStyle(.orange)
                    .onTapGesture(perform: beginEditing)
            } else {
                Text(block.answer)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(perform: beginEditing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(alignment: .leading) {
            if block.answer.isEmpty {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contextMenu {
            Button("Edit", action: beginEditing)
            Button("Delete", role: .destructive) {
                project = Stories.deleteBlock(project, blockId: block.id)
            }
        }
    }

    private func beginEditing() {
        draft = block.answer
        editing = true
    }

    private func commit() {
        project = Stories.editBlock(project, blockId: block.id, answer: draft)
        editing = false
    }
}
