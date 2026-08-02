import type { Block, Project } from '../types';
import { buildOutline, stats } from './outline';

function line(block: Block): string {
  const answer = block.answer.trim();

  // A free-form block is just the writer's sentence.
  if (block.prompt === '') {
    return answer === '' ? '- _(empty)_' : `- ${answer}`;
  }
  // Open threads stay visible. An outline that hides its holes is a worse
  // outline.
  if (answer === '') {
    return `- _${block.prompt}_ — **still open**`;
  }
  return `- _${block.prompt}_ ${answer}`;
}

/**
 * The blocks, assembled. Deliberately plain Markdown so it pastes cleanly into
 * Scrivener, Word, Docs, or a plain text file.
 */
export function toMarkdown(project: Project): string {
  const outline = buildOutline(project);
  const s = stats(project);
  const out: string[] = [`# ${project.title}`, ''];

  const summary =
    s.blocks === 0
      ? '_No blocks yet._'
      : `_${s.blocks} block${s.blocks === 1 ? '' : 's'}${
          s.open > 0 ? `, ${s.open} still open` : ''
        }._`;
  out.push(summary, '');

  for (const section of outline) {
    out.push(`## ${section.heading}`, '');
    for (const group of section.groups) {
      if (group.heading) out.push(`### ${group.heading}`, '');
      for (const block of group.blocks) out.push(line(block));
      out.push('');
    }
  }

  // Collapse the trailing blank line into a single terminating newline.
  return `${out.join('\n').trimEnd()}\n`;
}

export function slugify(title: string): string {
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug === '' ? 'writerblocks' : slug;
}
