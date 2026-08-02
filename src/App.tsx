import { useState } from 'react';
import { useProject } from './state/useProject';
import { AskView } from './components/AskView';
import { BoardView } from './components/BoardView';
import { OutlineView } from './components/OutlineView';
import { ProjectBar, type View } from './components/ProjectBar';

export function App() {
  const { library, project, dispatch, importFile } = useProject();
  const [view, setView] = useState<View>('ask');

  return (
    <div className="app">
      <ProjectBar
        library={library}
        project={project}
        view={view}
        onView={setView}
        dispatch={dispatch}
      />

      <main className="app__main">
        {view === 'ask' && (
          <AskView project={project} dispatch={dispatch} onGoToBoard={() => setView('board')} />
        )}
        {view === 'board' && <BoardView project={project} dispatch={dispatch} />}
        {view === 'outline' && <OutlineView project={project} onImport={importFile} />}
      </main>
    </div>
  );
}
