import { useEffect, useState } from 'react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import type { Block } from '../types';
import type { Dispatch } from '../state/useProject';

interface Props {
  block: Block;
  dispatch: Dispatch;
}

const MAX_ANSWER = 200;

export function BlockCard({ block, dispatch }: Props) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: block.id,
  });
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(block.answer);

  // Pick up changes made elsewhere (a drag, an import) while not editing.
  useEffect(() => {
    if (!editing) setDraft(block.answer);
  }, [block.answer, editing]);

  const commit = () => {
    setEditing(false);
    if (draft.trim() !== block.answer) dispatch({ type: 'editBlock', blockId: block.id, answer: draft });
  };

  return (
    <li
      ref={setNodeRef}
      className={`card${isDragging ? ' card--dragging' : ''}${block.answer === '' ? ' card--open' : ''}`}
      style={{ transform: CSS.Transform.toString(transform), transition }}
    >
      <div className="card__grip" {...attributes} {...listeners} aria-label="Reorder block">
        ⠿
      </div>

      <div className="card__body">
        {block.prompt !== '' && <p className="card__prompt">{block.prompt}</p>}

        {editing ? (
          <input
            className="card__input"
            autoFocus
            value={draft}
            maxLength={MAX_ANSWER}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commit();
              if (e.key === 'Escape') {
                setDraft(block.answer);
                setEditing(false);
              }
            }}
            aria-label={block.prompt || 'Block'}
          />
        ) : (
          <button className="card__answer" onClick={() => setEditing(true)} type="button">
            {block.answer === '' ? <span className="card__todo">still open</span> : block.answer}
          </button>
        )}
      </div>

      <button
        className="card__delete"
        type="button"
        title="Delete block"
        aria-label="Delete block"
        onClick={() => dispatch({ type: 'deleteBlock', blockId: block.id })}
      >
        ×
      </button>
    </li>
  );
}
