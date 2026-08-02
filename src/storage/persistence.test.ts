import { describe, expect, it } from 'vitest';
import { nextQuestion } from '../engine/deck';
import { toMarkdown } from '../engine/markdown';
import { applyAnswer, createProject } from '../engine/strands';
import { parseProject } from './persistence';

function populated() {
  let p = createProject('The Wreck');
  p = applyAnswer(p, nextQuestion(p)!, 'A diver goes back for the wreck.');
  p = applyAnswer(p, nextQuestion(p)!, 'Marla');
  p = applyAnswer(p, nextQuestion(p)!, 'A harbour town');
  return p;
}

describe('parseProject', () => {
  it('round-trips a real project through JSON unchanged', () => {
    const project = populated();
    const restored = parseProject(JSON.parse(JSON.stringify(project)));
    expect(restored).toEqual(project);
  });

  it('preserves the outline across a round trip', () => {
    const project = populated();
    const restored = parseProject(JSON.parse(JSON.stringify(project)))!;
    expect(toMarkdown(restored)).toBe(toMarkdown(project));
  });

  it('rejects things that are not projects', () => {
    expect(parseProject(null)).toBeNull();
    expect(parseProject('nope')).toBeNull();
    expect(parseProject({})).toBeNull();
    expect(parseProject({ strands: [], blocks: [] })).toBeNull();
    expect(parseProject({ strands: 'x', blocks: [] })).toBeNull();
  });

  it('drops malformed strands but keeps the good ones', () => {
    const project = populated();
    const raw = JSON.parse(JSON.stringify(project));
    raw.strands.push({ id: 'bad', type: 'not-a-type', label: 'x' });
    raw.strands.push(null);

    const restored = parseProject(raw)!;
    expect(restored.strands).toHaveLength(project.strands.length);
  });

  it('drops blocks orphaned by a missing strand', () => {
    const project = populated();
    const raw = JSON.parse(JSON.stringify(project));
    raw.blocks.push({ id: 'orphan', strandId: 'gone', answer: 'floating' });

    const restored = parseProject(raw)!;
    expect(restored.blocks.some((b) => b.id === 'orphan')).toBe(false);
    expect(restored.blocks).toHaveLength(project.blocks.length);
  });

  it('fills in missing fields rather than refusing the file', () => {
    const project = populated();
    const raw = JSON.parse(JSON.stringify(project));
    delete raw.title;
    delete raw.skipped;
    delete raw.createdAt;
    for (const b of raw.blocks) delete b.beat;

    const restored = parseProject(raw)!;
    expect(restored.title).toBe('Untitled story');
    expect(restored.skipped).toEqual({});
    expect(restored.blocks.every((b) => b.beat === null)).toBe(true);
  });

  it('sorts strands into order on the way in', () => {
    const project = populated();
    const raw = JSON.parse(JSON.stringify(project));
    raw.strands.reverse();

    const restored = parseProject(raw)!;
    const orders = restored.strands.map((s) => s.order);
    expect(orders).toEqual([...orders].sort((a, b) => a - b));
  });
});
