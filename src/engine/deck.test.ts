import { describe, expect, it } from 'vitest';
import { QUESTIONS } from '../data/questions';
import type { Project, Strand } from '../types';
import { nextQuestion, remainingCount, skipKey } from './deck';
import { applyAnswer, createProject, skipQuestion } from './strands';

function strandOfType(project: Project, type: Strand['type']): Strand {
  const strand = project.strands.find((s) => s.type === type);
  if (!strand) throw new Error(`no ${type} strand`);
  return strand;
}

function question(id: string) {
  const q = QUESTIONS.find((t) => t.id === id);
  if (!q) throw new Error(`no question ${id}`);
  return q;
}

/** Answer whatever is on top of the deck, `times` times. */
function answerMany(project: Project, times: number, answer = 'something'): Project {
  let p = project;
  for (let i = 0; i < times; i += 1) {
    const dealt = nextQuestion(p);
    if (!dealt) break;
    p = applyAnswer(p, dealt, answer);
  }
  return p;
}

/**
 * Every question the deck will currently offer for one strand, found by
 * skipping rather than answering so the gating stays fixed while we look.
 */
function offeredFor(project: Project, strandId: string): Set<string> {
  const ids = new Set<string>();
  let probe = project;
  for (;;) {
    const dealt = nextQuestion(probe, strandId);
    if (!dealt || dealt.strand.id !== strandId || ids.has(dealt.template.id)) break;
    ids.add(dealt.template.id);
    probe = skipQuestion(probe, strandId, dealt.template.id);
  }
  return ids;
}

describe('the deck', () => {
  it('opens with the logline', () => {
    expect(nextQuestion(createProject())?.template.id).toBe('logline');
  });

  it('asks who the main character is once the logline is down', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A diver goes back for the wreck.');
    expect(nextQuestion(p)?.template.id).toBe('main-character');
  });

  it('substitutes the subject into the question text', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    p = applyAnswer(p, nextQuestion(p)!, 'A harbour town');

    // With the premise questions spent, the deck turns to the people and places
    // the writer just named.
    const dealt = nextQuestion(p)!;
    expect(dealt.text).toMatch(/Marla|A harbour town/);
    expect(dealt.text).not.toContain('{subject}');
  });

  it('never asks the same one-off question twice for the same strand', () => {
    let p = createProject();
    const seen = new Set<string>();
    for (let i = 0; i < 60; i += 1) {
      const dealt = nextQuestion(p);
      if (!dealt) break;
      if (!dealt.template.repeatable) {
        const key = skipKey(dealt.strand.id, dealt.template.id);
        expect(seen.has(key)).toBe(false);
        seen.add(key);
      }
      p = applyAnswer(p, dealt, `answer ${i}`);
    }
  });

  it('keeps a gated question out of reach until its parent is answered', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    const marla = strandOfType(p, 'character');

    expect(offeredFor(p, marla.id)).not.toContain('char-likes-job');

    p = applyAnswer(p, { template: question('char-vocation'), strand: marla, text: 'Job?' }, 'She dives.');

    expect(offeredFor(p, marla.id)).toContain('char-likes-job');
  });

  it('does not unlock a follow-up on an empty "not sure yet" answer', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    const marla = strandOfType(p, 'character');

    p = applyAnswer(p, { template: question('char-vocation'), strand: marla, text: 'Job?' }, '   ');

    const offered = offeredFor(p, marla.id);
    expect(offered).not.toContain('char-likes-job');
    // ...and the question itself is spent, not re-asked.
    expect(offered).not.toContain('char-vocation');
  });

  it('sends a skipped question to the back rather than throwing it away', () => {
    const p = createProject();
    const first = nextQuestion(p)!;
    const skipped = skipQuestion(p, first.strand.id, first.template.id);

    expect(nextQuestion(skipped)?.template.id).not.toBe(first.template.id);
    // Still in the deck, just further down it.
    expect(remainingCount(skipped)).toBe(remainingCount(p));
    expect(offeredFor(skipped, first.strand.id)).toContain(first.template.id);
  });

  it('actually brings a skipped question back while the writer is still working', () => {
    // The UI promises nothing is ever lost. Answering keeps spawning new
    // subjects with fresh questions, so a skip that sorted behind *everything*
    // would in practice mean "never again".
    let p = createProject();
    const first = nextQuestion(p)!;
    p = skipQuestion(p, first.strand.id, first.template.id);

    let returnedAfter = -1;
    for (let i = 0; i < 40; i += 1) {
      const dealt = nextQuestion(p);
      if (!dealt) break;
      if (dealt.template.id === first.template.id && dealt.strand.id === first.strand.id) {
        returnedAfter = i;
        break;
      }
      p = applyAnswer(p, dealt, `answer ${i}`);
    }

    expect(returnedAfter).toBeGreaterThan(0);
    expect(returnedAfter).toBeLessThan(40);
  });

  it('scopes a skip to a single strand', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    p = applyAnswer(p, nextQuestion(p)!, 'A harbour town');
    p = applyAnswer(p, { template: question('another-character'), strand: strandOfType(p, 'premise'), text: 'Who else?' }, 'Jim');

    const [marla, jim] = p.strands.filter((s) => s.type === 'character');
    p = skipQuestion(p, marla!.id, 'char-like');

    expect(Object.keys(p.skipped)).toEqual([skipKey(marla!.id, 'char-like')]);
    // Jim is untouched by Marla's skip.
    expect(nextQuestion(p, jim!.id)?.template.id).toBe('char-like');
    expect(nextQuestion(p, marla!.id)?.template.id).not.toBe('char-like');
  });

  it('spreads questions across characters instead of burrowing into one', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    p = applyAnswer(p, nextQuestion(p)!, 'A harbour town');
    p = applyAnswer(p, { template: question('another-character'), strand: strandOfType(p, 'premise'), text: 'Who else?' }, 'Jim');

    const characters = p.strands.filter((s) => s.type === 'character');
    expect(characters).toHaveLength(2);

    const hits = new Map<string, number>();
    let probe = p;
    for (let i = 0; i < 10; i += 1) {
      const dealt = nextQuestion(probe);
      if (!dealt) break;
      hits.set(dealt.strand.id, (hits.get(dealt.strand.id) ?? 0) + 1);
      probe = applyAnswer(probe, dealt, 'x');
    }
    for (const c of characters) expect(hits.get(c.id) ?? 0).toBeGreaterThan(0);
  });

  it('honours a focus strand, then falls back once that strand runs dry', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    const marla = strandOfType(p, 'character');

    for (let i = 0; i < 5; i += 1) {
      const dealt = nextQuestion(p, marla.id);
      expect(dealt?.strand.id).toBe(marla.id);
      p = applyAnswer(p, dealt!, 'x');
    }

    // Drain Marla entirely; focus must fall back rather than dead-end.
    for (let i = 0; i < 100; i += 1) {
      const dealt = nextQuestion(p, marla.id);
      if (!dealt || dealt.strand.id !== marla.id) break;
      p = applyAnswer(p, dealt, 'x');
    }
    const after = nextQuestion(p, marla.id);
    expect(after).not.toBeNull();
    expect(after?.strand.id).not.toBe(marla.id);
  });

  it('never runs out, however long the writer keeps going', () => {
    // This is the point of the tool: the writer is never told there is nothing
    // more to say.
    const p = answerMany(createProject(), 300);
    expect(p.blocks).toHaveLength(300);
    expect(nextQuestion(p)).not.toBeNull();
    expect(remainingCount(p)).toBeGreaterThan(0);
  });

  it('keeps the open-ended questions available forever', () => {
    // "Who else is in this story?" is repeatable, so a strand whose one-off
    // questions are all spent still has something to offer.
    let p = createProject();
    const premise = strandOfType(p, 'premise');
    for (let i = 0; i < 40; i += 1) {
      const dealt = nextQuestion(p, premise.id);
      if (!dealt || dealt.strand.id !== premise.id) break;
      // Answer blank so nothing new spawns and the premise strand stays alone.
      p = applyAnswer(p, dealt, '');
    }

    const offered = offeredFor(p, premise.id);
    expect(offered).toContain('another-character');
    expect(offered).toContain('another-place');
    expect(offered).not.toContain('logline');
  });

  it('returns null only when there is nothing to ask about at all', () => {
    const empty: Project = { ...createProject(), strands: [] };
    expect(nextQuestion(empty)).toBeNull();
    expect(remainingCount(empty)).toBe(0);
  });

  it('stays fast as the project grows', () => {
    const p = answerMany(createProject(), 300);
    expect(p.blocks.length).toBe(300);

    const started = performance.now();
    for (let i = 0; i < 50; i += 1) nextQuestion(p);
    expect(performance.now() - started).toBeLessThan(1000);
  });
});
