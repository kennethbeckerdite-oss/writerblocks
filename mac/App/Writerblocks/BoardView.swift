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

    /// Grouped once for the whole board rather than each column re-filtering and
    /// re-sorting the entire project on every body evaluation.
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

            Text("Drag a card onto another; the line shows where it lands.")
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

    /// `displayIndex` counts the column as shown, including the card being
    /// dragged. The off-by-one that implies lives in the engine, where it is
    /// covered by tests.
    ///
    /// Deliberately not animated: renumbering `order` changes many blocks at
    /// once, and animating that while the list re-lays-out is what made a drop
    /// visibly jump before settling. The insertion line already showed where the
    /// card was going, so the animation carried no information.
    private func move(blockId: String, toStrandId: String, displayIndex: Int) -> Bool {
        guard project.blocks.contains(where: { $0.id == blockId }) else { return false }
        project = Stories.moveBlock(
            project, blockId: blockId, toStrandId: toStrandId, toDisplayIndex: displayIndex
        )
        return true
    }
}

// MARK: - Column

private struct StrandColumnView: View {
    @Binding var project: Project
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
                LazyVStack(spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        DroppableCard(
                            block: block,
                            strandId: strand.id,
                            displayIndex: index,
                            onMove: onMove,
                            onEdit: { answer in
                                project = Stories.editBlock(project, blockId: block.id, answer: answer)
                            },
                            onDelete: {
                                project = Stories.deleteBlock(project, blockId: block.id)
                            }
                        )
                    }

                    // Everything below the last card appends, so the bottom of a
                    // column is never dead space.
                    AppendZone(
                        isEmpty: blocks.isEmpty,
                        onDrop: { blockId in onMove(blockId, strand.id, blocks.count) }
                    )
                }
                .padding(8)
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
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
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

// MARK: - Drop targets

/// A card, and the drop target meaning "insert before me".
///
/// The whole card is the target, so there is no gap to aim at and nowhere in a
/// column to miss. The insertion line is drawn as an overlay, which does not
/// participate in layout — hovering therefore never reflows the column.
private struct DroppableCard: View {
    let block: Block
    let strandId: String
    let displayIndex: Int
    let onMove: (String, String, Int) -> Bool
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var targeted = false

    var body: some View {
        BlockCardView(block: block, onEdit: onEdit, onDelete: onDelete)
            .equatable()
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .offset(y: -5.5)
                    .opacity(targeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .draggable(block.id)
            .dropDestination(for: String.self) { ids, _ in
                targeted = false
                guard let dragged = ids.first, dragged != block.id else { return false }
                return onMove(dragged, strandId, displayIndex)
            } isTargeted: { targeted = $0 }
    }
}

/// The space below the last card. Fills the column so a drop anywhere beneath
/// the cards appends rather than doing nothing.
private struct AppendZone: View {
    let isEmpty: Bool
    let onDrop: (String) -> Bool

    @State private var targeted = false

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .opacity(targeted ? 1 : 0)

            if isEmpty {
                Text("Nothing here yet.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .top)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            targeted = false
            guard let dragged = ids.first else { return false }
            return onDrop(dragged)
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - Card

/// Takes a plain `Block` and closures rather than a binding to the whole
/// project, and is used through `.equatable()` so SwiftUI can skip re-rendering
/// cards that have not changed while a drag is in flight.
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
