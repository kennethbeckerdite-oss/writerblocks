import { useEffect, useMemo, useRef, useState } from 'react';
import type { Project } from '../types';
import type { Dispatch } from '../state/useProject';
import { nextQuestion } from '../engine/deck';
import { stats } from '../engine/outline';

interface Props {
  project: Project;
  dispatch: Dispatch;
  onGoToBoard: () => void;
}

const MAX_ANSWER = 200;

export function AskView({ project, dispatch, onGoToBoard }: Props) {
  const [focusStrandId, setFocusStrandId] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const dealt = useMemo(
    () => nextQuestion(project, focusStrandId),
    [project, focusStrandId],
  );
  const s = stats(project);

  // A focused strand that has been deleted should not silently keep filtering.
  useEffect(() => {
    if (focusStrandId && !project.strands.some((st) => st.id === focusStrandId)) {
      setFocusStrandId(null);
    }
  }, [project.strands, focusStrandId]);

  // Keep the caret where the writing happens, including after each answer.
  useEffect(() => {
    inputRef.current?.focus();
  }, [dealt?.template.id, dealt?.strand.id]);

  if (!dealt) {
    return (
      <div className="ask ask--empty">
        <p className="ask__question">Nothing left to ask.</p>
        <p className="ask__hint">Add a character or a place on the board and the questions start again.</p>
        <button className="btn" onClick={onGoToBoard}>
          Go to the board
        </button>
      </div>
    );
  }

  const submit = (answer: string) => {
    dispatch({ type: 'answer', dealt, answer });
    setDraft('');
  };

  const focusable = project.strands.filter((st) => st.type === 'character' || st.type === 'setting');

  return (
    <div className="ask">
      <div className="ask__strand">{dealt.strand.label}</div>

      <h2 className="ask__question">{dealt.text}</h2>

      {/* Coaching lives here, not in the question — the question text is stored
          on the block and read back in the outline. */}
      {dealt.template.hint && <p className="ask__coach">{dealt.template.hint}</p>}

      <form
        className="ask__form"
        onSubmit={(e) => {
          e.preventDefault();
          if (draft.trim() !== '') submit(draft);
        }}
      >
        <input
          ref={inputRef}
          className="ask__input"
          value={draft}
          maxLength={MAX_ANSWER}
          placeholder="One sentence…"
          onChange={(e) => setDraft(e.target.value)}
          aria-label={dealt.text}
        />
        <div className="ask__actions">
          <button className="btn btn--primary" type="submit" disabled={draft.trim() === ''}>
            Add block
          </button>
          <button
            className="btn btn--quiet"
            type="button"
            onClick={() => {
              dispatch({
                type: 'skip',
                strandId: dealt.strand.id,
                questionId: dealt.template.id,
              });
              setDraft('');
            }}
          >
            Skip for now
          </button>
          <button className="btn btn--quiet" type="button" onClick={() => submit('')}>
            Not sure yet
          </button>
        </div>
      </form>

      <p className="ask__hint">
        {draft.length > MAX_ANSWER - 40
          ? `${MAX_ANSWER - draft.length} characters left — if it needs more, it's two blocks.`
          : 'Skipping puts the question at the back of the deck. Nothing is ever lost.'}
      </p>

      {focusable.length > 0 && (
        <div className="ask__focus">
          <label htmlFor="focus">Keep asking me about</label>
          <select
            id="focus"
            value={focusStrandId ?? ''}
            onChange={(e) => setFocusStrandId(e.target.value === '' ? null : e.target.value)}
          >
            <option value="">anything</option>
            {focusable.map((st) => (
              <option key={st.id} value={st.id}>
                {st.label}
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Visible accumulation is the antidote to "I have nothing to say". */}
      <p className="ask__count">
        {s.blocks} block{s.blocks === 1 ? '' : 's'}
        {s.characters > 0 && ` · ${s.characters} character${s.characters === 1 ? '' : 's'}`}
        {s.settings > 0 && ` · ${s.settings} place${s.settings === 1 ? '' : 's'}`}
        {s.scenes > 0 && ` · ${s.scenes} scene${s.scenes === 1 ? '' : 's'}`}
      </p>
    </div>
  );
}
