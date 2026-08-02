/**
 * A strand is a subject the questions circle around: the premise itself, a
 * person, a place, or a moment in the story. Blocks hang off a strand.
 */
export type StrandType = 'premise' | 'character' | 'setting' | 'scene';

/**
 * Where a block lands when the blocks are assembled into an outline. This is
 * always derived from the strand a block currently sits on (see
 * `sectionForStrandType`), never stored — so dragging a block to another column
 * on the board moves it in the outline too, with nothing left to fall out of
 * sync.
 */
export type OutlineSection = 'premise' | 'character' | 'setting' | 'structure';

export interface Strand {
  id: string;
  type: StrandType;
  /** "Marla", "The diner", "Opening" — usually seeded from the answer that spawned it. */
  label: string;
  order: number;
  createdAt: number;
}

export interface Block {
  id: string;
  strandId: string;
  /** null for a free-form block the writer added themselves. */
  questionId: string | null;
  /** The question exactly as it was asked, with the subject already substituted. */
  prompt: string;
  /** One sentence. Empty means "not sure yet" — an open thread, not a failure. */
  answer: string;
  /** Chronological position in the story, for scene blocks. null = unplaced. */
  beat: number | null;
  /** Position within the strand. */
  order: number;
  createdAt: number;
}

export interface Project {
  id: string;
  title: string;
  schemaVersion: number;
  strands: Strand[];
  blocks: Block[];
  /**
   * Questions the writer skipped: `strandId::questionId` (skipping a question
   * about one character must not push it back for another) mapped to the block
   * count at the moment of the skip. The skip lapses once the writer has laid
   * down a few more blocks, so "skip for now" really does mean for now.
   */
  skipped: Record<string, number>;
  createdAt: number;
  updatedAt: number;
}

export interface QuestionTemplate {
  id: string;
  strandType: StrandType;
  /**
   * May contain {subject}, replaced with the strand's label when asked. Keep it
   * to the question itself — this text is stored on the block and read back in
   * the outline, so encouragement belongs in `hint`, not here.
   */
  text: string;
  /** Shown under the question while answering. Never stored on the block. */
  hint?: string;
  /** Lower is asked earlier. */
  priority: number;
  /** Answering this creates a new strand of the given type, named from the answer. */
  spawns?: StrandType;
  /** Question ids that only become askable once this one is answered. */
  unlocks?: string[];
  /** Scene questions only: where this sits in story chronology (0 = open, 100 = close). */
  beat?: number;
  /** Can be asked more than once for the same strand. */
  repeatable?: boolean;
}

/** What the deck hands back when it has something to ask. */
export interface DealtQuestion {
  template: QuestionTemplate;
  strand: Strand;
  /** template.text with {subject} resolved. */
  text: string;
}

/* ---- Outline shapes (built from blocks, never stored) ---- */

export interface OutlineGroup {
  /** The strand this group came from, or a synthetic grouping like "Other scenes". */
  key: string;
  heading: string | null;
  blocks: Block[];
}

export interface OutlineSectionView {
  section: OutlineSection;
  heading: string;
  groups: OutlineGroup[];
}

export type Outline = OutlineSectionView[];
