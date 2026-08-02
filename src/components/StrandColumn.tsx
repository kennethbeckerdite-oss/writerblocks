import { useState } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import type { Block, Strand } from '../types';
import type { Dispatch } from '../state/useProject';
import { BlockCard } from './BlockCard';

interface Props {
  strand: Strand;
  blocks: Block[];
  dispatch: Dispatch;
}

const TYPE_LABEL: Record<Strand['type'], string> = {
  premise: 'premise',
  character: 'character',
  setting: 'place',
  scene: 'scenes',
};

export function StrandColumn({ strand, blocks, dispatch }: Props) {
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState(strand.label);
  const [adding, setAdding] = useState('');

  // Lets an empty column still accept a dropped block.
  const { setNodeRef, isOver } = useDroppable({ id: `strand:${strand.id}` });

  const commitRename = () => {
    setRenaming(false);
    dispatch({ type: 'renameStrand', strandId: strand.id, label: draft });
  };

  const removable = strand.type === 'character' || strand.type === 'setting';

  return (
    <section className={`column${isOver ? ' column--over' : ''}`} ref={setNodeRef}>
      <header className="column__head">
        <div>
          {renaming ? (
            <input
              className="column__rename"
              autoFocus
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onBlur={commitRename}
              onKeyDown={(e) => {
                if (e.key === 'Enter') commitRename();
                if (e.key === 'Escape') {
                  setDraft(strand.label);
                  setRenaming(false);
                }
              }}
              aria-label="Strand name"
            />
          ) : (
            <button
              className="column__title"
              type="button"
              title={`${strand.label} — click to rename`}
              onClick={() => setRenaming(true)}
            >
              {strand.label}
            </button>
          )}
          <span className={`column__type column__type--${strand.type}`}>
            {TYPE_LABEL[strand.type]}
          </span>
        </div>

        {removable && (
          <button
            className="column__delete"
            type="button"
            title={`Delete ${strand.label} and its blocks`}
            aria-label={`Delete ${strand.label}`}
            onClick={() => {
              if (
                blocks.length === 0 ||
                confirm(`Delete "${strand.label}" and its ${blocks.length} block(s)?`)
              ) {
                dispatch({ type: 'deleteStrand', strandId: strand.id });
              }
            }}
          >
            ×
          </button>
        )}
      </header>

      <SortableContext items={blocks.map((b) => b.id)} strategy={verticalListSortingStrategy}>
        <ul className="column__blocks">
          {blocks.map((block) => (
            <BlockCard key={block.id} block={block} dispatch={dispatch} />
          ))}
          {blocks.length === 0 && <li className="column__empty">Nothing here yet.</li>}
        </ul>
      </SortableContext>

      <form
        className="column__add"
        onSubmit={(e) => {
          e.preventDefault();
          if (adding.trim() === '') return;
          dispatch({ type: 'addFreeBlock', strandId: strand.id, answer: adding });
          setAdding('');
        }}
      >
        <input
          value={adding}
          maxLength={200}
          placeholder="Add a block…"
          onChange={(e) => setAdding(e.target.value)}
          aria-label={`Add a block to ${strand.label}`}
        />
      </form>
    </section>
  );
}
