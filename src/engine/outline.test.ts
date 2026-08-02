import { describe, expect, it } from 'vitest';
import { QUESTIONS } from '../data/questions';
import type { Project } from '../types';
import { nextQuestion } from './deck';
import { toMarkdown } from './markdown';
import { buildOutline, sectionForStrandType, stats } from './outline';
import { addFreeBlock, addStrand, applyAnswer, createProject, moveBlock } from './strands';

function answerScene(project: Project, questionId: string, answer: string): Project {
  const scene = project.strands.find((s) => s.type === 'scene')!;
  const template = QUESTIONS.find((q) => q.id === questionId)!;
  return applyAnswer(project, { template, strand: scene, text: template.text }, answer);
}

/**
 * A small, populated project: a premise, one character and one place, each with
 * at least one block on it (a strand with no blocks is deliberately left out of
 * the outline, so the fixture has to give them one).
 */
function sampleProject(): Project {
  let p = createProject('The Wreck');
  p = applyAnswer(p, nextQuestion(p)!, 'A diver goes back for the wreck that killed her brother.');
  p = applyAnswer(p, nextQuestion(p)!, 'Marla');
  p = applyAnswer(p, nextQuestion(p)!, 'A harbour town');

  const marla = p.strands.find((s) => s.label === 'Marla')!;
  const town = p.strands.find((s) => s.label === 'A harbour town')!;
  p = applyAnswer(
    p,
    { template: QUESTIONS.find((q) => q.id === 'char-like')!, strand: marla, text: 'What do you like about Marla?' },
    'She never apologises.',
  );
  p = applyAnswer(
    p,
    { template: QUESTIONS.find((q) => q.id === 'place-smell')!, strand: town, text: 'What does A harbour town smell like?' },
    'Diesel and cold rope.',
  );
  return p;
}

describe('sectionForStrandType', () => {
  it('maps scenes into the structure section', () => {
    expect(sectionForStrandType('scene')).toBe('structure');
    expect(sectionForStrandType('premise')).toBe('premise');
    expect(sectionForStrandType('character')).toBe('character');
    expect(sectionForStrandType('setting')).toBe('setting');
  });
});

describe('buildOutline', () => {
  it('is empty for a project with no blocks', () => {
    expect(buildOutline(createProject())).toEqual([]);
  });

  it('orders sections premise, characters, places, structure', () => {
    let p = sampleProject();
    p = answerScene(p, 'scene-first', 'She signs the salvage papers.');

    expect(buildOutline(p).map((s) => s.section)).toEqual([
      'premise',
      'character',
      'setting',
      'structure',
    ]);
  });

  it('gives every character its own group, headed by name', () => {
    let p = sampleProject();
    p = addStrand(p, 'character', 'Jim');
    const jim = p.strands.find((s) => s.label === 'Jim')!;
    p = addFreeBlock(p, jim.id, 'He apologises constantly.');

    const characters = buildOutline(p).find((s) => s.section === 'character')!;
    expect(characters.groups.map((g) => g.heading)).toEqual(['Marla', 'Jim']);
  });

  it('leaves out strands that have no blocks yet', () => {
    let p = sampleProject();
    p = addStrand(p, 'character', 'Nobody');

    const characters = buildOutline(p).find((s) => s.section === 'character');
    expect(characters?.groups.map((g) => g.heading) ?? []).not.toContain('Nobody');
  });

  it('sorts scenes by beat no matter what order they were answered in', () => {
    let p = createProject('Backwards');
    p = answerScene(p, 'scene-last', 'She lets the boat go.');
    p = answerScene(p, 'scene-first', 'She signs the salvage papers.');
    p = answerScene(p, 'scene-midpoint', 'She finds the second body.');

    const structure = buildOutline(p).find((s) => s.section === 'structure')!;
    expect(structure.groups[0]?.blocks.map((b) => b.answer)).toEqual([
      'She signs the salvage papers.',
      'She finds the second body.',
      'She lets the boat go.',
    ]);
  });

  it('separates scenes that have no place in the chronology yet', () => {
    let p = createProject();
    p = answerScene(p, 'scene-first', 'She signs the papers.');
    p = answerScene(p, 'scene-dreading', 'Telling the mother.');

    const structure = buildOutline(p).find((s) => s.section === 'structure')!;
    expect(structure.groups).toHaveLength(2);
    expect(structure.groups[0]?.heading).toBeNull();
    expect(structure.groups[1]?.heading).toBe('Scenes not yet placed');
    expect(structure.groups[1]?.blocks.map((b) => b.answer)).toEqual(['Telling the mother.']);
  });

  it('follows a block that was dragged to another strand', () => {
    let p = sampleProject();
    const marla = p.strands.find((s) => s.label === 'Marla')!;
    const scene = p.strands.find((s) => s.type === 'scene')!;
    p = addFreeBlock(p, marla.id, 'She hums when she lies.');
    const block = p.blocks.find((b) => b.answer === 'She hums when she lies.')!;

    p = moveBlock(p, block.id, scene.id, 0);

    const outline = buildOutline(p);
    const characters = outline.find((s) => s.section === 'character');
    const structure = outline.find((s) => s.section === 'structure');
    expect(JSON.stringify(characters)).not.toContain('She hums when she lies.');
    expect(JSON.stringify(structure)).toContain('She hums when she lies.');
  });
});

describe('stats', () => {
  it('counts blocks, open threads, and strands', () => {
    let p = sampleProject();
    const marla = p.strands.find((s) => s.label === 'Marla')!;
    p = applyAnswer(
      p,
      { template: QUESTIONS.find((q) => q.id === 'char-afraid')!, strand: marla, text: 'Afraid?' },
      '',
    );

    const s = stats(p);
    expect(s.blocks).toBe(6);
    expect(s.answered).toBe(5);
    expect(s.open).toBe(1);
    expect(s.characters).toBe(1);
    expect(s.settings).toBe(1);
  });
});

describe('toMarkdown', () => {
  it('renders headings, sub-headings, and prompt-led lines', () => {
    let p = sampleProject();
    p = answerScene(p, 'scene-first', 'She signs the salvage papers.');
    const md = toMarkdown(p);

    expect(md.startsWith('# The Wreck\n')).toBe(true);
    expect(md).toContain('## Premise');
    expect(md).toContain('## Characters');
    expect(md).toContain('### Marla');
    expect(md).toContain('## Shape of the story');
    expect(md).toContain('- _Who is the main character?_ Marla');
    expect(md.endsWith('\n')).toBe(true);
    expect(md).not.toContain('\n\n\n');
  });

  it('shows open threads honestly instead of hiding them', () => {
    let p = sampleProject();
    const marla = p.strands.find((s) => s.label === 'Marla')!;
    p = applyAnswer(
      p,
      { template: QUESTIONS.find((q) => q.id === 'char-afraid')!, strand: marla, text: 'Afraid?' },
      '',
    );

    expect(toMarkdown(p)).toContain('**still open**');
  });

  it('renders a free-form block as a bare sentence', () => {
    let p = sampleProject();
    const marla = p.strands.find((s) => s.label === 'Marla')!;
    p = addFreeBlock(p, marla.id, 'She hums when she lies.');

    expect(toMarkdown(p)).toContain('- She hums when she lies.');
  });

  it('handles a project with nothing in it', () => {
    const md = toMarkdown(createProject('Empty'));
    expect(md).toContain('# Empty');
    expect(md).toContain('_No blocks yet._');
  });
});
