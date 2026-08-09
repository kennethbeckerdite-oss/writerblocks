import SwiftUI
import WriterblocksCore

/// Who is connected to whom.
///
/// The board answers "what have I written?"; this answers "who touches whom?".
/// Every line is derived from the sentences, and so is every dot's position —
/// nothing about the shape of this picture is stored.
struct WebView: View {
    @Binding var project: Project
    /// Take me to the Ask tab, on these two.
    let onAskAboutPair: (String, String) -> Void

    /// Held rather than recomputed: deriving the web walks every block against
    /// every character, and `body` reads it several times a pass.
    @State private var edges: [WebEdge] = []
    @State private var selectedEdgeId: String?
    @State private var dragFrom: String?
    @State private var dragPoint: CGPoint = .zero

    private static let space = "web"
    private static let nodeRadius: CGFloat = 30

    private var characters: [Strand] {
        project.strands.filter { $0.type == .character }.sorted { $0.order < $1.order }
    }

    private var selected: WebEdge? { edges.first { $0.id == selectedEdgeId } }

    var body: some View {
        HStack(spacing: 0) {
            graph

            if let selected {
                Divider()
                PairDetailView(
                    project: $project,
                    edge: selected,
                    onAsk: { onAskAboutPair(selected.a, selected.b) },
                    onClose: { selectedEdgeId = nil }
                )
                .frame(width: 320)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: project) { _, _ in refresh() }
    }

    private func refresh() {
        edges = Webs.edges(project)
        // The pair that was open may have gone with a deleted character.
        if let id = selectedEdgeId, !edges.contains(where: { $0.id == id }) {
            selectedEdgeId = nil
        }
    }

    // MARK: - The graph

    private var graph: some View {
        GeometryReader { geo in
            let points = positions(in: geo.size)

            ZStack {
                Canvas { context, _ in
                    for edge in edges {
                        guard let a = points[edge.a], let b = points[edge.b] else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)

                        // A faint line is a name the tool noticed. A solid one
                        // is a pair the writer has written something about.
                        let isSelected = edge.id == selectedEdgeId
                        let width: CGFloat = edge.isAnswered
                            ? min(5, 1 + CGFloat(edge.pairBlocks))
                            : 1
                        let colour: Color = edge.isAnswered
                            ? .accentColor.opacity(isSelected ? 1 : 0.75)
                            : .secondary.opacity(isSelected ? 0.8 : 0.35)

                        context.stroke(
                            path,
                            with: .color(colour),
                            lineWidth: isSelected ? width + 2 : width
                        )
                    }

                    if let dragFrom, let a = points[dragFrom] {
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: dragPoint)
                        context.stroke(
                            path,
                            with: .color(.accentColor),
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                    }
                }
                .allowsHitTesting(false)

                ForEach(characters) { strand in
                    if let point = points[strand.id] {
                        node(strand, at: point, points: points)
                    }
                }

                if edges.isEmpty {
                    Text("No one is connected yet.\nName someone in another character's answer, or drag one onto another.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .coordinateSpace(.named(Self.space))
            .gesture(
                SpatialTapGesture(coordinateSpace: .named(Self.space))
                    .onEnded { value in
                        selectedEdgeId = edge(nearest: value.location, points: points)?.id
                    }
            )
        }
        .overlay(alignment: .bottom) {
            Text("Drag one character onto another to connect them.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 10)
        }
    }

    private func node(_ strand: Strand, at point: CGPoint, points: [String: CGPoint]) -> some View {
        let isTarget = dragFrom != nil
            && dragFrom != strand.id
            && target(in: points) == strand.id

        return VStack(spacing: 5) {
            Circle()
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    Circle().stroke(
                        isTarget ? Color.accentColor : Color.secondary.opacity(0.45),
                        lineWidth: isTarget ? 3 : 1.5
                    )
                )
                .frame(width: Self.nodeRadius * 2, height: Self.nodeRadius * 2)
                .overlay(
                    Text(initials(strand.label))
                        .font(.system(size: 15, weight: .medium, design: .serif))
                )

            Text(strand.label)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 130)
        }
        .position(x: point.x, y: point.y)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    dragFrom = strand.id
                    dragPoint = value.location
                }
                .onEnded { _ in
                    let onto = target(in: points)
                    dragFrom = nil
                    guard let onto, onto != strand.id else { return }

                    project = Stories.linkCharacters(
                        project, strandId: strand.id, aboutStrandId: onto
                    )
                    refresh()
                    selectedEdgeId = edges.first {
                        ($0.a == strand.id && $0.b == onto) || ($0.a == onto && $0.b == strand.id)
                    }?.id
                }
        )
    }

    // MARK: - Geometry

    /// Characters evenly around a circle, in the order they joined the story.
    ///
    /// Computed, never stored: no coordinates in the story file, no physics to
    /// settle, and the same picture every time it is opened.
    private func positions(in size: CGSize) -> [String: CGPoint] {
        let all = characters
        guard !all.isEmpty else { return [:] }

        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        if all.count == 1 { return [all[0].id: centre] }

        let radius = max(80, min(size.width, size.height) / 2 - Self.nodeRadius - 46)
        var out: [String: CGPoint] = [:]
        for (i, strand) in all.enumerated() {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(all.count)
            out[strand.id] = CGPoint(
                x: centre.x + radius * cos(angle),
                y: centre.y + radius * sin(angle)
            )
        }
        return out
    }

    /// Whichever dot the drag is currently over.
    private func target(in points: [String: CGPoint]) -> String? {
        guard dragFrom != nil else { return nil }
        return points.first { _, point in
            hypot(dragPoint.x - point.x, dragPoint.y - point.y) <= Self.nodeRadius + 10
        }?.key
    }

    private func edge(nearest point: CGPoint, points: [String: CGPoint]) -> WebEdge? {
        var best: (edge: WebEdge, distance: CGFloat)?
        for edge in edges {
            guard let a = points[edge.a], let b = points[edge.b] else { continue }
            let d = distance(from: point, toSegment: a, b)
            guard d <= 14 else { continue }
            if best == nil || d < best!.distance { best = (edge, d) }
        }
        return best?.edge
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }

        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func initials(_ label: String) -> String {
        let words = label.split(whereSeparator: { $0.isWhitespace })
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// Everything written about one pair, both ways round.
private struct PairDetailView: View {
    @Binding var project: Project
    let edge: WebEdge
    let onAsk: () -> Void
    let onClose: () -> Void

    private func label(_ id: String) -> String {
        project.strands.first { $0.id == id }?.label ?? "someone"
    }

    private var blocks: [Block] {
        project.blocks
            .filter { block in
                guard let about = block.aboutStrandId else { return false }
                return (block.strandId == edge.a && about == edge.b)
                    || (block.strandId == edge.b && about == edge.a)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("\(label(edge.a)) and \(label(edge.b))")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close")
            }

            if blocks.isEmpty {
                Text(mentionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(blocks) { block in
                            BlockCardView(
                                block: block,
                                onEdit: { answer in
                                    project = Stories.editBlock(project, blockId: block.id, answer: answer)
                                },
                                onDelete: {
                                    project = Stories.deleteBlock(project, blockId: block.id)
                                }
                            )
                            .equatable()
                        }
                    }
                }
            }

            Button("Ask about these two", action: onAsk)
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var mentionSummary: String {
        let times = edge.mentions == 1 ? "once" : "\(edge.mentions) times"
        return "One of them turns up in the other's answers \(times), "
            + "but nothing has been written about the two of them yet."
    }
}
