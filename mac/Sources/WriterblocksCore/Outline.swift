import Foundation

/// A block's outline section always comes from the strand it currently sits on,
/// so moving a card on the board moves it in the outline too.
public func sectionForStrandType(_ type: StrandType) -> OutlineSection {
    switch type {
    case .premise: return .premise
    case .character: return .character
    case .setting: return .setting
    case .scene: return .structure
    }
}

public struct ProjectStats: Equatable, Sendable {
    public let blocks: Int
    public let answered: Int
    public let open: Int
    public let characters: Int
    public let settings: Int
    public let scenes: Int
}

public enum OutlineBuilder {

    private static let sectionOrder: [OutlineSection] = [.premise, .character, .setting, .structure]

    private static let headings: [OutlineSection: String] = [
        .premise: "Premise",
        .character: "Characters",
        .setting: "Setting",
        .structure: "Shape of the story"
    ]

    /// Scenes read in story order — a writer who answered the ending first
    /// should still see the opening at the top. Beated scenes sort by beat;
    /// anything unplaced keeps its manual order and follows in its own group.
    private static func structureGroups(_ blocks: [Block]) -> [OutlineGroup] {
        let placed = blocks
            .filter { $0.beat != nil }
            .sorted { a, b in
                let ab = a.beat ?? 0, bb = b.beat ?? 0
                return ab != bb ? ab < bb : a.order < b.order
            }
        let loose = blocks.filter { $0.beat == nil }.sorted { $0.order < $1.order }

        var groups: [OutlineGroup] = []
        if !placed.isEmpty {
            groups.append(OutlineGroup(id: "in-order", heading: nil, blocks: placed))
        }
        if !loose.isEmpty {
            groups.append(OutlineGroup(id: "unplaced", heading: "Scenes not yet placed", blocks: loose))
        }
        return groups
    }

    /// Settings, each followed by the locations inside it.
    ///
    /// The thing that can be left out is the whole subtree, not the strand. A
    /// setting the writer has said nothing about but has put three locations
    /// inside still has to appear, or those locations lose the heading that
    /// says where they are — so a setting here may legitimately be a heading
    /// with nothing under it.
    ///
    /// Sorting by `order` alone would interleave: make Cheyenne, the 7-11,
    /// Portland, then Cheyenne's kitchen, and the kitchen files under Portland.
    private static func placeGroups(_ project: Project, _ places: [Strand]) -> [OutlineGroup] {
        func blocks(of strand: Strand) -> [Block] {
            project.blocks.filter { $0.strandId == strand.id }.sorted { $0.order < $1.order }
        }

        // Reading a story file normalises a parent that does not hold up, but a
        // Project can also be built in code — so anything whose setting is not
        // here stands on its own rather than vanishing.
        let settingIds = Set(places.filter { $0.parentStrandId == nil }.map(\.id))
        func standsAlone(_ strand: Strand) -> Bool {
            guard let parent = strand.parentStrandId else { return true }
            return !settingIds.contains(parent)
        }

        var groups: [OutlineGroup] = []
        for setting in places where standsAlone(setting) {
            let own = blocks(of: setting)
            let inside = places
                .filter { $0.parentStrandId == setting.id }
                .map { (strand: $0, blocks: blocks(of: $0)) }
                .filter { !$0.blocks.isEmpty }

            if own.isEmpty && inside.isEmpty { continue }

            groups.append(OutlineGroup(id: setting.id, heading: setting.label, blocks: own))
            for location in inside {
                groups.append(
                    OutlineGroup(
                        id: location.strand.id,
                        heading: location.strand.label,
                        blocks: location.blocks,
                        depth: 1
                    )
                )
            }
        }
        return groups
    }

    public static func build(_ project: Project) -> Outline {
        let strands = project.strands.sorted { $0.order < $1.order }
        var sections: Outline = []

        for section in sectionOrder {
            let relevant = strands.filter { sectionForStrandType($0.type) == section }
            if relevant.isEmpty { continue }

            let groups: [OutlineGroup]

            if section == .structure {
                // All scene strands pool together so the chronology is one spine.
                let pooled = relevant.flatMap { strand in
                    project.blocks.filter { $0.strandId == strand.id }
                }
                groups = structureGroups(pooled)
            } else if section == .setting {
                groups = placeGroups(project, relevant)
            } else {
                groups = relevant.compactMap { strand in
                    let blocks = project.blocks
                        .filter { $0.strandId == strand.id }
                        .sorted { $0.order < $1.order }
                    if blocks.isEmpty { return nil }
                    return OutlineGroup(
                        id: strand.id,
                        // The premise needs no sub-heading; it is the section.
                        heading: section == .premise ? nil : strand.label,
                        blocks: blocks
                    )
                }
            }

            if groups.isEmpty { continue }
            sections.append(
                OutlineSectionView(section: section, heading: headings[section] ?? "", groups: groups)
            )
        }

        return sections
    }

    public static func stats(_ project: Project) -> ProjectStats {
        let answered = project.blocks.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        func count(_ type: StrandType) -> Int {
            project.strands.filter { $0.type == type }.count
        }

        let sceneStrandIds = Set(project.strands.filter { $0.type == .scene }.map(\.id))
        let sceneBlocks = project.blocks.filter { sceneStrandIds.contains($0.strandId) }.count

        return ProjectStats(
            blocks: project.blocks.count,
            answered: answered,
            open: project.blocks.count - answered,
            characters: count(.character),
            settings: count(.setting),
            scenes: sceneBlocks
        )
    }
}
