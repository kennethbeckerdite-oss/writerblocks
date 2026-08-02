import { useCallback, useEffect, useMemo, useReducer, useRef } from 'react';
import type { DealtQuestion, Project, StrandType } from '../types';
import {
  addFreeBlock,
  addStrand,
  applyAnswer,
  createProject,
  deleteBlock,
  deleteStrand,
  editBlock,
  moveBlock,
  renameProject,
  renameStrand,
  skipQuestion,
} from '../engine/strands';
import { type Library, loadLibrary, readProjectFile, saveLibrary } from '../storage/persistence';

type Action =
  | { type: 'answer'; dealt: DealtQuestion; answer: string }
  | { type: 'skip'; strandId: string; questionId: string }
  | { type: 'addStrand'; strandType: StrandType; label: string }
  | { type: 'renameStrand'; strandId: string; label: string }
  | { type: 'deleteStrand'; strandId: string }
  | { type: 'addFreeBlock'; strandId: string; answer: string }
  | { type: 'editBlock'; blockId: string; answer: string }
  | { type: 'deleteBlock'; blockId: string }
  | { type: 'moveBlock'; blockId: string; toStrandId: string; toIndex: number }
  | { type: 'renameProject'; title: string }
  | { type: 'newProject' }
  | { type: 'selectProject'; projectId: string }
  | { type: 'deleteProject'; projectId: string }
  | { type: 'importProject'; project: Project };

/** Apply a pure engine transform to whichever project is active. */
function onActive(library: Library, fn: (project: Project) => Project): Library {
  return {
    ...library,
    projects: library.projects.map((p) => (p.id === library.activeId ? fn(p) : p)),
  };
}

function reduce(library: Library, action: Action): Library {
  switch (action.type) {
    case 'answer':
      return onActive(library, (p) => applyAnswer(p, action.dealt, action.answer));
    case 'skip':
      return onActive(library, (p) => skipQuestion(p, action.strandId, action.questionId));
    case 'addStrand':
      return onActive(library, (p) => addStrand(p, action.strandType, action.label));
    case 'renameStrand':
      return onActive(library, (p) => renameStrand(p, action.strandId, action.label));
    case 'deleteStrand':
      return onActive(library, (p) => deleteStrand(p, action.strandId));
    case 'addFreeBlock':
      return onActive(library, (p) => addFreeBlock(p, action.strandId, action.answer));
    case 'editBlock':
      return onActive(library, (p) => editBlock(p, action.blockId, action.answer));
    case 'deleteBlock':
      return onActive(library, (p) => deleteBlock(p, action.blockId));
    case 'moveBlock':
      return onActive(library, (p) =>
        moveBlock(p, action.blockId, action.toStrandId, action.toIndex),
      );
    case 'renameProject':
      return onActive(library, (p) => renameProject(p, action.title));

    case 'newProject': {
      const project = createProject();
      return { projects: [...library.projects, project], activeId: project.id };
    }
    case 'importProject':
      return { projects: [...library.projects, action.project], activeId: action.project.id };
    case 'selectProject':
      return library.projects.some((p) => p.id === action.projectId)
        ? { ...library, activeId: action.projectId }
        : library;
    case 'deleteProject': {
      const projects = library.projects.filter((p) => p.id !== action.projectId);
      // Never leave the writer with no project at all.
      if (projects.length === 0) {
        const project = createProject();
        return { projects: [project], activeId: project.id };
      }
      return {
        projects,
        activeId: library.activeId === action.projectId ? projects[0]!.id : library.activeId,
      };
    }
  }
}

const SAVE_DEBOUNCE_MS = 400;

export function useProject() {
  const [library, dispatch] = useReducer(reduce, undefined, loadLibrary);

  // Debounced autosave. The reducer stays pure; only this effect touches disk.
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (timer.current !== null) clearTimeout(timer.current);
    timer.current = setTimeout(() => saveLibrary(library), SAVE_DEBOUNCE_MS);
    return () => {
      if (timer.current !== null) clearTimeout(timer.current);
    };
  }, [library]);

  // A pending debounce would otherwise be lost if the tab closes.
  const latest = useRef(library);
  latest.current = library;
  useEffect(() => {
    const flush = () => saveLibrary(latest.current);
    window.addEventListener('beforeunload', flush);
    return () => {
      window.removeEventListener('beforeunload', flush);
      flush();
    };
  }, []);

  const project = useMemo(
    () => library.projects.find((p) => p.id === library.activeId) ?? library.projects[0]!,
    [library],
  );

  const importFile = useCallback(async (file: File) => {
    dispatch({ type: 'importProject', project: await readProjectFile(file) });
  }, []);

  return { library, project, dispatch, importFile };
}

export type Dispatch = ReturnType<typeof useProject>['dispatch'];
