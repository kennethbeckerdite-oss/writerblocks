import { useMemo, useRef, useState } from 'react';
import type { Project } from '../types';
import { buildOutline, stats } from '../engine/outline';
import { toMarkdown } from '../engine/markdown';
import { downloadMarkdown, downloadProjectJson } from '../storage/persistence';

interface Props {
  project: Project;
  onImport: (file: File) => Promise<void>;
}

export function OutlineView({ project, onImport }: Props) {
  const outline = useMemo(() => buildOutline(project), [project]);
  const markdown = useMemo(() => toMarkdown(project), [project]);
  const s = stats(project);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  async function copy() {
    try {
      await navigator.clipboard.writeText(markdown);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      setError('Could not reach the clipboard — use Download .md instead.');
    }
  }

  return (
    <div className="outline">
      <div className="outline__bar">
        <button className="btn btn--primary" type="button" onClick={copy} disabled={s.blocks === 0}>
          {copied ? 'Copied' : 'Copy as Markdown'}
        </button>
        <button
          className="btn"
          type="button"
          onClick={() => downloadMarkdown(project, markdown)}
          disabled={s.blocks === 0}
        >
          Download .md
        </button>
        <button className="btn" type="button" onClick={() => downloadProjectJson(project)}>
          Export .json
        </button>
        <button className="btn" type="button" onClick={() => fileRef.current?.click()}>
          Import .json
        </button>
        <input
          ref={fileRef}
          className="visually-hidden"
          type="file"
          accept="application/json,.json"
          onChange={async (e) => {
            const file = e.target.files?.[0];
            e.target.value = '';
            if (!file) return;
            setError(null);
            try {
              await onImport(file);
            } catch (err) {
              setError(err instanceof Error ? err.message : 'That file could not be read.');
            }
          }}
        />
      </div>

      {error && <p className="outline__error">{error}</p>}

      {outline.length === 0 ? (
        <p className="outline__empty">
          No blocks yet. Answer a question or two and the outline builds itself.
        </p>
      ) : (
        <article className="outline__doc">
          <h1>{project.title}</h1>
          <p className="outline__meta">
            {s.blocks} block{s.blocks === 1 ? '' : 's'}
            {s.open > 0 && `, ${s.open} still open`}
          </p>

          {outline.map((section) => (
            <section key={section.section}>
              <h2>{section.heading}</h2>
              {section.groups.map((group) => (
                <div key={group.key}>
                  {group.heading && <h3>{group.heading}</h3>}
                  <ul>
                    {group.blocks.map((block) => (
                      <li key={block.id}>
                        {block.prompt !== '' && <em>{block.prompt} </em>}
                        {block.answer === '' ? (
                          <span className="outline__open">still open</span>
                        ) : (
                          block.answer
                        )}
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </section>
          ))}
        </article>
      )}
    </div>
  );
}
