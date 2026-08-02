import { GATED_IDS, QUESTIONS, parentsOf } from '../data/questions';
import type { DealtQuestion, Project, QuestionTemplate, Strand } from '../types';

/**
 * Skips are recorded per strand, not per question: skipping "what do you like
 * about Marla?" must not also push the question back for Jim.
 */
export function skipKey(strandId: string, questionId: string): string {
  return `${strandId}::${questionId}`;
}

export function renderQuestion(text: string, strand: Strand): string {
  return text.replaceAll('{subject}', strand.label);
}

/**
 * One pass over the blocks, so choosing a question stays linear in the size of
 * the project rather than scanning every block once per strand per question.
 */
interface Tally {
  /** `strandId::questionId` -> times asked, whether or not it got an answer. */
  asked: Map<string, number>;
  /** `strandId::questionId` -> times it came back with an actual sentence. */
  answered: Map<string, number>;
  /** strandId -> how many blocks hang off it. */
  perStrand: Map<string, number>;
}

function tally(project: Project): Tally {
  const asked = new Map<string, number>();
  const answered = new Map<string, number>();
  const perStrand = new Map<string, number>();

  for (const b of project.blocks) {
    perStrand.set(b.strandId, (perStrand.get(b.strandId) ?? 0) + 1);
    if (b.questionId === null) continue;
    const key = skipKey(b.strandId, b.questionId);
    asked.set(key, (asked.get(key) ?? 0) + 1);
    if (b.answer.trim() !== '') answered.set(key, (answered.get(key) ?? 0) + 1);
  }

  return { asked, answered, perStrand };
}

/**
 * A gated question opens only once a parent has been genuinely answered for the
 * same strand. "Not sure yet" does not open it — there is no point asking
 * whether they like a job we have not named.
 */
function isUnlocked(t: Tally, template: QuestionTemplate, strand: Strand): boolean {
  if (!GATED_IDS.has(template.id)) return true;
  const parents = parentsOf(template.id);
  return parents.some((parentId) => (t.answered.get(skipKey(strand.id, parentId)) ?? 0) > 0);
}

interface Candidate {
  template: QuestionTemplate;
  strand: Strand;
  /** Repeatable questions drift later each time they are used, so they never dominate. */
  effectivePriority: number;
  strandBlocks: number;
}

/**
 * How many blocks the writer has to lay down before a skipped question comes
 * back. This is deliberately measured in blocks rather than in priority: every
 * answer can spawn a new subject carrying two dozen fresh questions, so any
 * fixed priority penalty — however large — can be outrun forever, and "skip
 * for now" would quietly become "never again".
 */
const SKIP_COOLDOWN_BLOCKS = 8;

/** Sinks a question below everything else without removing it from the deck. */
const SKIP_PENALTY = 1000;

function candidates(project: Project): Candidate[] {
  const t = tally(project);
  const out: Candidate[] = [];

  const stillCoolingOff = (key: string): boolean => {
    const skippedAt = project.skipped[key];
    return skippedAt !== undefined && project.blocks.length - skippedAt < SKIP_COOLDOWN_BLOCKS;
  };

  for (const strand of project.strands) {
    const strandBlocks = t.perStrand.get(strand.id) ?? 0;

    for (const template of QUESTIONS) {
      if (template.strandType !== strand.type) continue;

      const key = skipKey(strand.id, template.id);
      const asked = t.asked.get(key) ?? 0;
      if (asked > 0 && !template.repeatable) continue;
      if (!isUnlocked(t, template, strand)) continue;

      out.push({
        template,
        strand,
        effectivePriority:
          template.priority +
          (template.repeatable ? asked * 5 : 0) +
          (stillCoolingOff(key) ? SKIP_PENALTY : 0),
        strandBlocks,
      });
    }
  }

  return out;
}

function compare(a: Candidate, b: Candidate): number {
  if (a.effectivePriority !== b.effectivePriority) {
    return a.effectivePriority - b.effectivePriority;
  }
  // Same question, several strands: ask about the thinnest one, so the web
  // grows outward instead of burrowing into whoever came first.
  if (a.strandBlocks !== b.strandBlocks) return a.strandBlocks - b.strandBlocks;
  if (a.strand.order !== b.strand.order) return a.strand.order - b.strand.order;
  return a.template.id.localeCompare(b.template.id);
}

/**
 * The next thing to ask. `focusStrandId` biases toward one subject ("keep
 * asking me about Marla") but falls back to the whole deck once that strand is
 * exhausted, rather than dead-ending.
 */
export function nextQuestion(
  project: Project,
  focusStrandId?: string | null,
): DealtQuestion | null {
  const all = candidates(project);
  if (all.length === 0) return null;

  const pool =
    focusStrandId && all.some((c) => c.strand.id === focusStrandId)
      ? all.filter((c) => c.strand.id === focusStrandId)
      : all;

  const best = pool.reduce((a, b) => (compare(b, a) < 0 ? b : a));
  return {
    template: best.template,
    strand: best.strand,
    text: renderQuestion(best.template.text, best.strand),
  };
}

/** How many questions are still on the table — for the "you are not empty" counter. */
export function remainingCount(project: Project): number {
  return candidates(project).length;
}
