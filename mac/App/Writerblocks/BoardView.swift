import SwiftUI
import WriterblocksCore

/// Where a dragged block would land if it were dropped right now.
private struct DropTarget: Equatable {
    let strandId: String
    /// Index in the column's list *including* the block being dragged.
    let index: Int
}

/// Every block as a card, grouped in columns. Drag to reorder, drag between
/// columns; a block's column decides where it lands in the outline.
struct BoardView: View {
    @Binding var project: Project

    @State private var newStrandType: StrandType = .character
    @State private var newStrandLabel = ""
    @State private var dropTarget: DropTarget?

    private var strands: [Strand] {
        project.strands.sorted { $0.order < $1.order }
    }

    /// Grouped once here rather than each column filtering the whole project on
    /// every body evaluation — that recomputation is what made dragging stutter.
    private var blocksByStrand: [String: [Block]] {
        var grouped: [String: [Block]] = [:]
        for block in project.blocks { grouped[block.strandId, default: []].append(block) }
        for key in grouped.keys { grouped[key]?.sort { $0.order < $1.order } }
        return grouped
    }

    var body: some View {
        let grouped = blocksByStrand

        VStack(spacing: 0) {
            addBar
            Divider()

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(strands) { strand in
                        StrandColumnView(
                            project: $project,
                            dropTarget: $dropTarget,
                            strand: strand,
                            blocks: grouped[strand.id] ?? [],
                            onMove: move
                        )
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

            Text("Drag a card by its text; the line shows where it lands.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private func addStrand() {
        let label = newStrandLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        project = Stories.addStrand(project, type: newStrandType, label: label)
        newStrandLabel = ""
    }

    /// `zoneIndex` counts the gaps in the column as displayed. The off-by-one
    /// that comes with that lives in `Stories.moveBlock(toDisplayIndex:)`, where
    /// it is covered by tests.
    private func move(blockId: String, toStrandId: String, zoneIndex: Int) -> Bool {
        guard project.blocks.contains(where: { $0.id == blockId }) else { return false }

        withAnimation(.easeOut(duration: 0.16)) {
            project = Stories.moveBlock(
                project, blockId: blockId, toStrandId: toStrandId, toDisplayIndex: zoneIndex
            )
        }
        return true
    }
}

// MARK: - Column

private struct StrandColumnView: View {
    @Binding var project: Project
    @Binding var dropTarget: DropTarget?
    let strand: Strand
    let blocks: [Block]
    let onMove: (String, String, Int) -> Bool

    @State private var renaming = false
    @State private var draftLabel = ""
    @State private var newBlock = ""

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
                // Spacing is zero because the insertion zones *are* the gaps —
                // so there is nowhere ambiguous to drop.
                LazyVStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        insertionZone(at: index)

                        BlockCardView(
                            block: block,
                            onEdit: { answer in
                                project = Stories.editBlock(project, blockId: block.id, answer: answer)
                            },
                            onDelete: {
                                project = Stories.deleteBlock(project, blockId: block.id)
                            }
                        )
                        .draggable(block.id)
                    }

                    // The last zone fills whatever is left, so dropping anywhere
                    // below the cards appends rather than doing nothing.
                    insertionZone(at: blocks.count, fills: true)

                    if blocks.isEmpty {
                        Text("Nothing here yet.")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 460)

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
                .stroke(
                    dropTarget?.strandId == strand.id
                        ? Color.accentColor.opacity(0.6)
                        : Color.secondary.opacity(0.25),
                    lineWidth: 1
                )
        )
    }

    private func insertionZone(at index: Int, fills: Bool = false) -> some View {
        InsertionZone(
            isActive: dropTarget == DropTarget(strandId: strand.id, index: index),
            fills: fills,
            onTargeted: { targeted in
                let target = DropTarget(strandId: strand.id, index: index)
                if targeted {
                    dropTarget = target
                } else if dropTarget == target {
                    dropTarget = nil
                }
            },
            onDrop: { blockId in
                dropTarget = nil
                return onMove(blockId, strand.id, index)
            }
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
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete \(strand.label) and its blocks")
            }
        }
        .padding(10)
    }
}

// MARK: - Insertion zone

/// The gap between two cards, and the only place a block can be dropped. Being
/// an explicit target is what lets the board show a line for where the block is
/// going instead of leaving the writer to guess.
private struct InsertionZone: View {
    let isActive: Bool
    let fills: Bool
    let onTargeted: (Bool) -> Void
    let onDrop: (String) -> Bool

    var body: some View {
        Rectangle()
            .fill(isActive ? Color.accentColor : Color.clear)
            .frame(height: isActive ? 3 : 2)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
            .padding(.vertical, 4)
            .frame(minHeight: fills ? 44 : nil, alignment: .top)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { ids, _ in
                guard let blockId = ids.first else { return false }
                return onDrop(blockId)
            } isTargeted: { onTargeted($0) }
    }
}

// MARK: - Card

/// Takes a plain `Block` and closures rather than a binding to the whole
/// project, so SwiftUI can leave untouched cards alone while a drag is in
/// flight.
private struct BlockCardView: View, Equatable {
    let block: Block
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var editing = false
    @State private var draft = ""

    static func == (lhs: BlockCardView, rhs: BlockCardView) -> Bool {
        lhs.block == rhs.block
    }

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
                    .onSubmit {
                        onEdit(draft)
                        editing = false
                    }
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
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func beginEditing() {
        draft = block.answer
        editing = true
    }
}
