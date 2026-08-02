import { useMemo, useState } from 'react';
import {
  DndContext,
  type DragEndEvent,
  KeyboardSensor,
  PointerSensor,
  closestCorners,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import { sortableKeyboardCoordinates } from '@dnd-kit/sortable';
import type { Block, Project, StrandType } from '../types';
import type { Dispatch } from '../state/useProject';
import { StrandColumn } from './StrandColumn';

interface Props {
  project: Project;
  dispatch: Dispatch;
}

const COLUMN_PREFIX = 'strand:';

export function BoardView({ project, dispatch }: Props) {
  const [newStrandType, setNewStrandType] = useState<StrandType>('character');
  const [newStrandLabel, setNewStrandLabel] = useState('');

  const sensors = useSensors(
    // A small drag threshold so clicking a card to edit it still works.
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const strands = useMemo(
    () => [...project.strands].sort((a, b) => a.order - b.order),
    [project.strands],
  );

  const blocksByStrand = useMemo(() => {
    const map = new Map<string, Block[]>();
    for (const strand of strands) map.set(strand.id, []);
    for (const block of project.blocks) map.get(block.strandId)?.push(block);
    for (const list of map.values()) list.sort((a, b) => a.order - b.order);
    return map;
  }, [project.blocks, strands]);

  function handleDragEnd({ active, over }: DragEndEvent) {
    if (!over) return;
    const blockId = String(active.id);
    const overId = String(over.id);
    if (blockId === overId) return;

    // A block can be dropped onto another block, or onto a column's empty space.
    const overIsColumn = overId.startsWith(COLUMN_PREFIX);
    const targetStrandId = overIsColumn
      ? overId.slice(COLUMN_PREFIX.length)
      : project.blocks.find((b) => b.id === overId)?.strandId;
    if (!targetStrandId) return;

    const list = blocksByStrand.get(targetStrandId) ?? [];
    const toIndex = overIsColumn ? list.length : list.findIndex((b) => b.id === overId);
    dispatch({ type: 'moveBlock', blockId, toStrandId: targetStrandId, toIndex });
  }

  return (
    <div className="board">
      <form
        className="board__add"
        onSubmit={(e) => {
          e.preventDefault();
          if (newStrandLabel.trim() === '') return;
          dispatch({ type: 'addStrand', strandType: newStrandType, label: newStrandLabel });
          setNewStrandLabel('');
        }}
      >
        <select
          value={newStrandType}
          onChange={(e) => setNewStrandType(e.target.value as StrandType)}
          aria-label="What kind of strand"
        >
          <option value="character">Character</option>
          <option value="setting">Place</option>
          <option value="scene">Scenes</option>
        </select>
        <input
          value={newStrandLabel}
          placeholder="Name it…"
          onChange={(e) => setNewStrandLabel(e.target.value)}
          aria-label="Name of the new strand"
        />
        <button className="btn" type="submit" disabled={newStrandLabel.trim() === ''}>
          Add
        </button>
      </form>

      <DndContext sensors={sensors} collisionDetection={closestCorners} onDragEnd={handleDragEnd}>
        <div className="board__columns">
          {strands.map((strand) => (
            <StrandColumn
              key={strand.id}
              strand={strand}
              blocks={blocksByStrand.get(strand.id) ?? []}
              dispatch={dispatch}
            />
          ))}
        </div>
      </DndContext>
    </div>
  );
}
