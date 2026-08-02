import type { Block, Project, Strand } from '../types';
import { SCHEMA_VERSION, createProject } from '../engine/strands';
import { slugify } from '../engine/markdown';

const KEY = 'writerblocks:v1';

export interface Library {
  projects: Project[];
  activeId: string;
}

/* ---- validation ---------------------------------------------------------- */

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' ? v : fallback;
}

function num(v: unknown, fallback = 0): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

const STRAND_TYPES = new Set(['premise', 'character', 'setting', 'scene']);

function parseStrand(v: unknown, index: number): Strand | null {
  if (!isRecord(v)) return null;
  const type = str(v.type);
  if (!STRAND_TYPES.has(type)) return null;
  const id = str(v.id);
  if (id === '') return null;
  return {
    id,
    type: type as Strand['type'],
    label: str(v.label, 'Untitled'),
    order: num(v.order, index),
    createdAt: num(v.createdAt, Date.now()),
  };
}

function parseBlock(v: unknown, index: number, strandIds: Set<string>): Block | null {
  if (!isRecord(v)) return null;
  const id = str(v.id);
  const strandId = str(v.strandId);
  // A block whose strand is gone has nowhere to live.
  if (id === '' || !strandIds.has(strandId)) return null;
  return {
    id,
    strandId,
    questionId: typeof v.questionId === 'string' ? v.questionId : null,
    prompt: str(v.prompt),
    answer: str(v.answer),
    beat: typeof v.beat === 'number' && Number.isFinite(v.beat) ? v.beat : null,
    order: num(v.order, index),
    createdAt: num(v.createdAt, Date.now()),
  };
}

function parseSkipped(v: unknown): Record<string, number> {
  if (!isRecord(v)) return {};
  const out: Record<string, number> = {};
  for (const [key, at] of Object.entries(v)) {
    if (typeof at === 'number' && Number.isFinite(at)) out[key] = at;
  }
  return out;
}

/**
 * Rebuild a project from untrusted JSON — a stored blob from an older build, or
 * a file someone was handed. Anything unreadable is dropped rather than thrown:
 * a corrupt store must never cost a writer their session.
 */
export function parseProject(v: unknown): Project | null {
  if (!isRecord(v)) return null;
  if (!Array.isArray(v.strands) || !Array.isArray(v.blocks)) return null;

  const strands = v.strands
    .map((s, i) => parseStrand(s, i))
    .filter((s): s is Strand => s !== null);
  if (strands.length === 0) return null;

  const strandIds = new Set(strands.map((s) => s.id));
  const blocks = v.blocks
    .map((b, i) => parseBlock(b, i, strandIds))
    .filter((b): b is Block => b !== null);

  const now = Date.now();
  return {
    id: str(v.id) || crypto.randomUUID(),
    title: str(v.title, 'Untitled story'),
    schemaVersion: SCHEMA_VERSION,
    strands: [...strands].sort((a, b) => a.order - b.order),
    blocks,
    skipped: parseSkipped(v.skipped),
    createdAt: num(v.createdAt, now),
    updatedAt: num(v.updatedAt, now),
  };
}

/* ---- the library --------------------------------------------------------- */

function freshLibrary(): Library {
  const project = createProject();
  return { projects: [project], activeId: project.id };
}

export function loadLibrary(): Library {
  let raw: string | null = null;
  try {
    raw = localStorage.getItem(KEY);
  } catch {
    // Private browsing, storage disabled — run in memory rather than fail.
    return freshLibrary();
  }
  if (!raw) return freshLibrary();

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!isRecord(parsed) || !Array.isArray(parsed.projects)) return freshLibrary();

    const projects = parsed.projects
      .map(parseProject)
      .filter((p): p is Project => p !== null);
    if (projects.length === 0) return freshLibrary();

    const activeId = str(parsed.activeId);
    return {
      projects,
      activeId: projects.some((p) => p.id === activeId) ? activeId : projects[0]!.id,
    };
  } catch {
    return freshLibrary();
  }
}

export function saveLibrary(library: Library): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(library));
  } catch {
    // Quota exceeded or storage unavailable. Losing the write is bad but
    // crashing mid-sentence is worse.
  }
}

/* ---- files --------------------------------------------------------------- */

function download(filename: string, contents: string, mime: string): void {
  const url = URL.createObjectURL(new Blob([contents], { type: mime }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export function downloadProjectJson(project: Project): void {
  download(
    `${slugify(project.title)}.writerblocks.json`,
    JSON.stringify(project, null, 2),
    'application/json',
  );
}

export function downloadMarkdown(project: Project, markdown: string): void {
  download(`${slugify(project.title)}.md`, markdown, 'text/markdown');
}

/** Read a `.writerblocks.json` file back into a project with a fresh id. */
export async function readProjectFile(file: File): Promise<Project> {
  const project = parseProject(JSON.parse(await file.text()));
  if (!project) throw new Error('That does not look like a writerblocks file.');
  return { ...project, id: crypto.randomUUID() };
}
