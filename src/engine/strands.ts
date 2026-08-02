import type { Block, DealtQuestion, Project, Strand, StrandType } from '../types';
import { skipKey } from './deck';

export const SCHEMA_VERSION = 1;

const MAX_LABEL = 40;

function id(): string {
  return crypto.randomUUID();
}

function now(): number {
  return Date.now();
}

function touch(project: Project, patch: Partial<Project>): Project {
  return { ...project, ...patch, updatedAt: now() };
}

function blocksOf(project: Project, strandId: string): Block[] {
  return project.blocks
    .filter((b) => b.strandId === strandId)
    .sort((a, b) => a.order - b.order);
}

function nextOrder(project: Project, strandId: string): number {
  const existing = blocksOf(project, strandId);
  const last = existing[existing.length - 1];
  return last ? last.order + 1 : 0;
}

/**
 * Turn an answer into a strand name: "A diner off the interstate." becomes
 * "A diner off the interstate". Long answers are clipped rather than rejected —
 * the writer can rename the strand on the board.
 */
export function labelFromAnswer(answer: string): string {
  const cleaned = answer.trim().replace(/\s+/g, ' ').replace(/[.,;:]+$/, '');
  if (cleaned === '') return 'Untitled';
  if (cleaned.length <= MAX_LABEL) return cleaned;
  return `${cleaned.slice(0, MAX_LABEL - 1).trimEnd()}…`;
}

export function createProject(title = 'Untitled story'): Project {
  const t = now();
  const strands: Strand[] = [
    { id: id(), type: 'premise', label: 'Premise', order: 0, createdAt: t },
    { id: id(), type: 'scene', label: 'Scenes', order: 1, createdAt: t },
  ];
  return {
    id: id(),
    title,
    schemaVersion: SCHEMA_VERSION,
    strands,
    blocks: [],
    skipped: {},
    createdAt: t,
    updatedAt: t,
  };
}

export function addStrand(project: Project, type: StrandType, label: string): Project {
  const orders = project.strands.map((s) => s.order);
  const strand: Strand = {
    id: id(),
    type,
    label: label.trim() === '' ? 'Untitled' : label.trim(),
    order: orders.length > 0 ? Math.max(...orders) + 1 : 0,
    createdAt: now(),
  };
  return touch(project, { strands: [...project.strands, strand] });
}

export function renameStrand(project: Project, strandId: string, label: string): Project {
  const trimmed = label.trim();
  if (trimmed === '') return project;
  return touch(project, {
    strands: project.strands.map((s) => (s.id === strandId ? { ...s, label: trimmed } : s)),
  });
}

/** Deletes the strand and everything hanging off it. */
export function deleteStrand(project: Project, strandId: string): Project {
  return touch(project, {
    strands: project.strands.filter((s) => s.id !== strandId),
    blocks: project.blocks.filter((b) => b.strandId !== strandId),
  });
}

/**
 * Record an answer. An empty answer is legitimate — it becomes an open thread
 * that shows up in the outline as a hole, which is more useful than pretending
 * the question was never asked.
 */
export function applyAnswer(project: Project, dealt: DealtQuestion, answer: string): Project {
  const trimmed = answer.trim();
  const block: Block = {
    id: id(),
    strandId: dealt.strand.id,
    questionId: dealt.template.id,
    prompt: dealt.text,
    answer: trimmed,
    beat: dealt.template.beat ?? null,
    order: nextOrder(project, dealt.strand.id),
    createdAt: now(),
  };

  // Answering clears any earlier skip of this question for this strand.
  const { [skipKey(dealt.strand.id, dealt.template.id)]: _cleared, ...skipped } = project.skipped;

  let next = touch(project, { blocks: [...project.blocks, block], skipped });

  // "Who is the main character?" doesn't just record a block, it opens a new
  // subject to ask about. A blank answer opens nothing.
  if (dealt.template.spawns && trimmed !== '') {
    next = addStrand(next, dealt.template.spawns, labelFromAnswer(trimmed));
  }

  return next;
}

/** Steps a question aside, remembering how far along the writer was at the time. */
export function skipQuestion(project: Project, strandId: string, questionId: string): Project {
  const key = skipKey(strandId, questionId);
  if (key in project.skipped) return project;
  return touch(project, {
    skipped: { ...project.skipped, [key]: project.blocks.length },
  });
}

/** A block the writer wrote unprompted. */
export function addFreeBlock(project: Project, strandId: string, answer: string): Project {
  const block: Block = {
    id: id(),
    strandId,
    questionId: null,
    prompt: '',
    answer: answer.trim(),
    beat: null,
    order: nextOrder(project, strandId),
    createdAt: now(),
  };
  return touch(project, { blocks: [...project.blocks, block] });
}

export function editBlock(project: Project, blockId: string, answer: string): Project {
  return touch(project, {
    blocks: project.blocks.map((b) => (b.id === blockId ? { ...b, answer: answer.trim() } : b)),
  });
}

export function deleteBlock(project: Project, blockId: string): Project {
  return touch(project, { blocks: project.blocks.filter((b) => b.id !== blockId) });
}

/**
 * Move a block to `toIndex` within `toStrandId`, renumbering both the source
 * and destination strands so `order` stays a dense 0..n-1 run.
 */
export function moveBlock(
  project: Project,
  blockId: string,
  toStrandId: string,
  toIndex: number,
): Project {
  const moving = project.blocks.find((b) => b.id === blockId);
  if (!moving) return project;
  if (!project.strands.some((s) => s.id === toStrandId)) return project;

  const fromStrandId = moving.strandId;
  const source = blocksOf(project, fromStrandId).filter((b) => b.id !== blockId);
  const target = fromStrandId === toStrandId ? source : blocksOf(project, toStrandId);

  const clamped = Math.max(0, Math.min(toIndex, target.length));
  const relocated: Block = { ...moving, strandId: toStrandId };
  const merged = [...target.slice(0, clamped), relocated, ...target.slice(clamped)];

  const renumbered = new Map<string, Block>();
  merged.forEach((b, i) => renumbered.set(b.id, { ...b, order: i }));
  if (fromStrandId !== toStrandId) {
    source.forEach((b, i) => renumbered.set(b.id, { ...b, order: i }));
  }

  return touch(project, {
    blocks: project.blocks.map((b) => renumbered.get(b.id) ?? b),
  });
}

export function renameProject(project: Project, title: string): Project {
  const trimmed = title.trim();
  return touch(project, { title: trimmed === '' ? 'Untitled story' : trimmed });
}
