import type {
  Block,
  Outline,
  OutlineGroup,
  OutlineSection,
  OutlineSectionView,
  Project,
  StrandType,
} from '../types';

/**
 * A block's outline section always comes from the strand it currently sits on,
 * so moving a card on the board moves it in the outline too.
 */
export function sectionForStrandType(type: StrandType): OutlineSection {
  switch (type) {
    case 'premise':
      return 'premise';
    case 'character':
      return 'character';
    case 'setting':
      return 'setting';
    case 'scene':
      return 'structure';
  }
}

const SECTION_ORDER: OutlineSection[] = ['premise', 'character', 'setting', 'structure'];

const SECTION_HEADINGS: Record<OutlineSection, string> = {
  premise: 'Premise',
  character: 'Characters',
  setting: 'Places',
  structure: 'Shape of the story',
};

function byOrder(a: Block, b: Block): number {
  return a.order - b.order;
}

/**
 * Scenes read in story order — a writer who answered the ending first should
 * still see the opening at the top. Beated scenes sort by beat; anything
 * unplaced keeps its manual order and follows in its own group.
 */
function structureGroups(blocks: Block[]): OutlineGroup[] {
  const placed = blocks.filter((b) => b.beat !== null).sort((a, b) => {
    const beatDelta = (a.beat as number) - (b.beat as number);
    return beatDelta !== 0 ? beatDelta : a.order - b.order;
  });
  const loose = blocks.filter((b) => b.beat === null).sort(byOrder);

  const groups: OutlineGroup[] = [];
  if (placed.length > 0) groups.push({ key: 'in-order', heading: null, blocks: placed });
  if (loose.length > 0) {
    groups.push({ key: 'unplaced', heading: 'Scenes not yet placed', blocks: loose });
  }
  return groups;
}

export function buildOutline(project: Project): Outline {
  const strands = [...project.strands].sort((a, b) => a.order - b.order);
  const sections: OutlineSectionView[] = [];

  for (const section of SECTION_ORDER) {
    const relevant = strands.filter((s) => sectionForStrandType(s.type) === section);
    if (relevant.length === 0) continue;

    let groups: OutlineGroup[];

    if (section === 'structure') {
      // All scene strands pool together so the chronology is one spine.
      const pooled = relevant.flatMap((s) => project.blocks.filter((b) => b.strandId === s.id));
      groups = structureGroups(pooled);
    } else {
      groups = relevant
        .map((strand) => ({
          key: strand.id,
          // The premise needs no sub-heading; it is the section.
          heading: section === 'premise' ? null : strand.label,
          blocks: project.blocks.filter((b) => b.strandId === strand.id).sort(byOrder),
        }))
        .filter((g) => g.blocks.length > 0);
    }

    if (groups.length === 0) continue;
    sections.push({ section, heading: SECTION_HEADINGS[section], groups });
  }

  return sections;
}

export interface ProjectStats {
  blocks: number;
  answered: number;
  open: number;
  characters: number;
  settings: number;
  scenes: number;
}

export function stats(project: Project): ProjectStats {
  const answered = project.blocks.filter((b) => b.answer.trim() !== '').length;
  const count = (type: StrandType) => project.strands.filter((s) => s.type === type).length;
  const sceneBlocks = project.strands
    .filter((s) => s.type === 'scene')
    .reduce((n, s) => n + project.blocks.filter((b) => b.strandId === s.id).length, 0);

  return {
    blocks: project.blocks.length,
    answered,
    open: project.blocks.length - answered,
    characters: count('character'),
    settings: count('setting'),
    scenes: sceneBlocks,
  };
}
