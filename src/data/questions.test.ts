import { describe, expect, it } from 'vitest';
import { GATED_IDS, QUESTIONS, getQuestion, parentsOf } from './questions';

/**
 * The deck is meant to be rewritten by whoever is using the tool. These are the
 * rules an edited deck still has to obey, so a bad edit fails here rather than
 * halfway through someone's writing session.
 */
describe('the question deck', () => {
  it('has unique ids', () => {
    const ids = QUESTIONS.map((q) => q.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('only unlocks questions that exist', () => {
    for (const q of QUESTIONS) {
      for (const childId of q.unlocks ?? []) {
        expect(getQuestion(childId), `${q.id} unlocks missing ${childId}`).toBeDefined();
      }
    }
  });

  it('unlocks only within the same strand type, so a parent can actually be answered', () => {
    for (const q of QUESTIONS) {
      for (const childId of q.unlocks ?? []) {
        expect(getQuestion(childId)?.strandType, `${q.id} -> ${childId}`).toBe(q.strandType);
      }
    }
  });

  it('gives every gated question a findable parent', () => {
    for (const id of GATED_IDS) {
      expect(parentsOf(id).length, `${id} has no parent`).toBeGreaterThan(0);
    }
  });

  it('has no question that gates itself', () => {
    for (const q of QUESTIONS) {
      expect(q.unlocks ?? []).not.toContain(q.id);
    }
  });

  it('uses {subject} only where the strand has a real name', () => {
    // Premise and scene strands are named "Premise" and "Scenes" — substituting
    // those into a question produces nonsense.
    for (const q of QUESTIONS) {
      if (q.strandType === 'premise' || q.strandType === 'scene') {
        expect(q.text, q.id).not.toContain('{subject}');
      }
    }
  });

  it('names the character in every question that opens a fresh thread', () => {
    // A gated follow-up is exempt: "what's standing in the way of that?" is
    // asked right after its parent, which already named who we mean.
    for (const q of QUESTIONS) {
      if (q.strandType === 'character' && !GATED_IDS.has(q.id)) {
        expect(q.text, `${q.id} never names its character`).toContain('{subject}');
      }
    }
  });

  it('puts beats only on scene questions', () => {
    for (const q of QUESTIONS) {
      if (q.beat !== undefined) expect(q.strandType, q.id).toBe('scene');
    }
  });

  it('spawns new strands only from the premise', () => {
    for (const q of QUESTIONS) {
      if (q.spawns) expect(q.strandType, q.id).toBe('premise');
    }
  });

  it('keeps coaching in the hint, not in the question text', () => {
    // The question text is stored on the block and read back in the outline;
    // a long compound question makes for a bad outline line.
    for (const q of QUESTIONS) {
      expect(q.text.length, `${q.id} is too long to read back in an outline`).toBeLessThan(70);
      if (q.hint) expect(q.text).not.toContain(q.hint);
    }
  });

  it('asks something in every section', () => {
    for (const type of ['premise', 'character', 'setting', 'scene'] as const) {
      expect(QUESTIONS.filter((q) => q.strandType === type).length).toBeGreaterThan(3);
    }
  });
});
