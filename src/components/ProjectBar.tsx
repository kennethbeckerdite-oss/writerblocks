import { useEffect, useState } from 'react';
import type { Project } from '../types';
import type { Library } from '../storage/persistence';
import type { Dispatch } from '../state/useProject';

export type View = 'ask' | 'board' | 'outline';

interface Props {
  library: Library;
  project: Project;
  view: View;
  onView: (view: View) => void;
  dispatch: Dispatch;
}

const VIEWS: { id: View; label: string }[] = [
  { id: 'ask', label: 'Ask' },
  { id: 'board', label: 'Board' },
  { id: 'outline', label: 'Outline' },
];

export function ProjectBar({ library, project, view, onView, dispatch }: Props) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(project.title);

  useEffect(() => {
    if (!editing) setDraft(project.title);
  }, [project.title, editing]);

  const commit = () => {
    setEditing(false);
    dispatch({ type: 'renameProject', title: draft });
  };

  return (
    <header className="bar">
      <div className="bar__left">
        <span className="bar__brand">writerblocks</span>

        {editing ? (
          <input
            className="bar__rename"
            autoFocus
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commit();
              if (e.key === 'Escape') {
                setDraft(project.title);
                setEditing(false);
              }
            }}
            aria-label="Story title"
          />
        ) : (
          <button className="bar__title" type="button" onClick={() => setEditing(true)}>
            {project.title}
          </button>
        )}
      </div>

      <nav className="bar__views">
        {VIEWS.map((v) => (
          <button
            key={v.id}
            type="button"
            className={`bar__view${view === v.id ? ' bar__view--on' : ''}`}
            aria-current={view === v.id}
            onClick={() => onView(v.id)}
          >
            {v.label}
          </button>
        ))}
      </nav>

      <div className="bar__right">
        {library.projects.length > 1 && (
          <select
            className="bar__projects"
            value={project.id}
            onChange={(e) => dispatch({ type: 'selectProject', projectId: e.target.value })}
            aria-label="Switch story"
          >
            {library.projects.map((p) => (
              <option key={p.id} value={p.id}>
                {p.title}
              </option>
            ))}
          </select>
        )}
        <button className="btn btn--quiet" type="button" onClick={() => dispatch({ type: 'newProject' })}>
          New story
        </button>
      </div>
    </header>
  );
}
