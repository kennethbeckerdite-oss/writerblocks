import { describe, expect, it } from 'vitest';
import { QUESTIONS } from '../data/questions';
import type { Project } from '../types';
import { nextQuestion } from './deck';
import {
  addFreeBlock,
  addStrand,
  applyAnswer,
  createProject,
  deleteBlock,
  deleteStrand,
  editBlock,
  labelFromAnswer,
  moveBlock,
  renameStrand,
} from './strands';

function orderedIds(project: Project, strandId: string): string[] {
  return project.blocks
    .filter((b) => b.strandId === strandId)
    .sort((a, b) => a.order - b.order)
    .map((b) => b.answer);
}

describe('labelFromAnswer', () => {
  it('strips trailing punctuation and collapses whitespace', () => {
    expect(labelFromAnswer('  The   diner.  ')).toBe('The diner');
  });

  it('clips a long answer instead of rejecting it', () => {
    const label = labelFromAnswer('a'.repeat(120));
    expect(label.length).toBeLessThanOrEqual(40);
    expect(label.endsWith('…')).toBe(true);
  });

  it('falls back rather than producing an empty name', () => {
    expect(labelFromAnswer('   ')).toBe('Untitled');
  });
});

describe('applyAnswer', () => {
  it('spawns a strand named from the answer', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla.');

    const character = p.strands.find((s) => s.type === 'character');
    expect(character?.label).toBe('Marla');
  });

  it('spawns nothing when the writer is not sure yet', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    const before = p.strands.length;
    p = applyAnswer(p, nextQuestion(p)!, '');

    expect(p.strands).toHaveLength(before);
    // The question is still recorded, as an open thread.
    expect(p.blocks.some((b) => b.questionId === 'main-character' && b.answer === '')).toBe(true);
  });

  it('carries the beat through to the block', () => {
    let p = createProject();
    const scene = p.strands.find((s) => s.type === 'scene')!;
    const first = QUESTIONS.find((q) => q.id === 'scene-first')!;
    p = applyAnswer(p, { template: first, strand: scene, text: 'First scene?' }, 'A boat.');

    expect(p.blocks[0]?.beat).toBe(first.beat);
  });

  it('records the question with the name already filled in, as it was asked', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'A logline.');
    p = applyAnswer(p, nextQuestion(p)!, 'Marla');
    const marla = p.strands.find((s) => s.label === 'Marla')!;

    const template = QUESTIONS.find((q) => q.id === 'char-like')!;
    const dealt = { template, strand: marla, text: 'What do you like about Marla?' };
    p = applyAnswer(p, dealt, 'She never apologises.');

    const block = p.blocks[p.blocks.length - 1]!;
    expect(block.prompt).toBe('What do you like about Marla?');
    expect(block.prompt).not.toContain('{subject}');
  });

  it('gives each new block the next order in its strand', () => {
    let p = createProject();
    p = applyAnswer(p, nextQuestion(p)!, 'one');
    p = applyAnswer(p, nextQuestion(p)!, 'two');
    const premise = p.strands.find((s) => s.type === 'premise')!;
    expect(orderedIds(p, premise.id)).toEqual(['one', 'two']);
  });
});

describe('board edits', () => {
  it('renames a strand and refuses a blank name', () => {
    let p = addStrand(createProject(), 'character', 'Marla');
    const strand = p.strands.find((s) => s.label === 'Marla')!;
    p = renameStrand(p, strand.id, '  Marla Vance  ');
    expect(p.strands.find((s) => s.id === strand.id)?.label).toBe('Marla Vance');

    p = renameStrand(p, strand.id, '   ');
    expect(p.strands.find((s) => s.id === strand.id)?.label).toBe('Marla Vance');
  });

  it('deletes a strand along with its blocks', () => {
    let p = addStrand(createProject(), 'character', 'Marla');
    const strand = p.strands.find((s) => s.label === 'Marla')!;
    p = addFreeBlock(p, strand.id, 'She hums when she lies.');
    expect(p.blocks).toHaveLength(1);

    p = deleteStrand(p, strand.id);
    expect(p.strands.some((s) => s.id === strand.id)).toBe(false);
    expect(p.blocks).toHaveLength(0);
  });

  it('edits and deletes a block', () => {
    let p = createProject();
    const premise = p.strands.find((s) => s.type === 'premise')!;
    p = addFreeBlock(p, premise.id, 'first thought');
    const block = p.blocks[0]!;

    p = editBlock(p, block.id, '  second thought  ');
    expect(p.blocks[0]?.answer).toBe('second thought');

    p = deleteBlock(p, block.id);
    expect(p.blocks).toHaveLength(0);
  });
});

describe('moveBlock', () => {
  function threeBlocks(): { project: Project; strandId: string; otherId: string } {
    let p = createProject();
    p = addStrand(p, 'character', 'Marla');
    p = addStrand(p, 'character', 'Jim');
    const strandId = p.strands.find((s) => s.label === 'Marla')!.id;
    const otherId = p.strands.find((s) => s.label === 'Jim')!.id;
    p = addFreeBlock(p, strandId, 'a');
    p = addFreeBlock(p, strandId, 'b');
    p = addFreeBlock(p, strandId, 'c');
    return { project: p, strandId, otherId };
  }

  it('reorders within a strand', () => {
    const { project, strandId } = threeBlocks();
    const c = project.blocks.find((b) => b.answer === 'c')!;
    const moved = moveBlock(project, c.id, strandId, 0);
    expect(orderedIds(moved, strandId)).toEqual(['c', 'a', 'b']);
  });

  it('moves a block to another strand and renumbers both', () => {
    const { project, strandId, otherId } = threeBlocks();
    const b = project.blocks.find((b) => b.answer === 'b')!;
    const moved = moveBlock(project, b.id, otherId, 0);

    expect(orderedIds(moved, strandId)).toEqual(['a', 'c']);
    expect(orderedIds(moved, otherId)).toEqual(['b']);
    expect(moved.blocks.filter((x) => x.strandId === strandId).map((x) => x.order)).toEqual([0, 1]);
  });

  it('clamps an out-of-range index instead of dropping the block', () => {
    const { project, strandId } = threeBlocks();
    const a = project.blocks.find((b) => b.answer === 'a')!;
    const moved = moveBlock(project, a.id, strandId, 99);
    expect(orderedIds(moved, strandId)).toEqual(['b', 'c', 'a']);
  });

  it('ignores a move to a strand that does not exist', () => {
    const { project } = threeBlocks();
    const a = project.blocks.find((b) => b.answer === 'a')!;
    expect(moveBlock(project, a.id, 'nope', 0)).toBe(project);
  });
});
