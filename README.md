# writerblocks

Small questions, stacked into blocks, assembled into a first outline.

A **native macOS app** is being built in [`mac/`](mac) — see
[Building the Mac app](#building-the-mac-app). It is the real destination: a
story becomes a `.writerblocks` file you own, which Time Machine backs up,
iCloud Drive syncs, and git can version.

The **web version** was the visual prototype and is still live at
[kennethbeckerdite-oss.github.io/writerblocks](https://kennethbeckerdite-oss.github.io/writerblocks/).
It will be removed once the Mac app replaces it.

> **If you have written anything in the web version, export it now.** Its work
> lives in one browser's local storage and nowhere else. Use **Export .json** —
> the Mac app reads exactly that format, and there is a test proving it.

## The idea

In *Zen and the Art of Motorcycle Maintenance*, a student can't write a
five-hundred-word essay about the United States. So she's told to write about
Bozeman. Still nothing. Then about the main street of Bozeman. Then about the
front of one building on it. Then about a single brick — upper left-hand brick,
start there. She comes back with five thousand words.

Writer's block is usually not an absence of material. It's the fear of having
nothing to say, and that fear grows with the size of the question. So this tool
never asks a big question.

It asks: *What's the logline?* Then: *Who is the main character?* Then: *What
does she do for a living? Does she like that job? What would she rather be
doing?* Every answer is one sentence, and every sentence becomes a **block**.
Blocks stack into **strands** — a person, a place, a run of scenes — and the
strands assemble into an outline you can take somewhere else and actually
write.

There is no AI in this. Nothing here calls a model, and the app makes no network
requests at all. The value is the question, not a machine's opinion about your
story.

## Building the Mac app

Needs a Mac with Xcode, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) — the repo holds a readable `project.yml` instead of a
`.pbxproj` that conflicts on every edit.

```sh
cd mac/App
xcodegen generate          # writes Writerblocks.xcodeproj (gitignored)
open Writerblocks.xcodeproj
```

Then ⌘R. The app is unsigned, which is fine for running it yourself; signing is
only needed to hand it to somebody else.

The engine is a plain Swift package and needs no Xcode project at all:

```sh
swift test --package-path mac      # 70 tests
```

Both are built and tested on a real Mac by
[`.github/workflows/mac.yml`](.github/workflows/mac.yml) on every push.

### How it is put together

`mac/Sources/WriterblocksCore/` is the engine — deck selection, story
mutations, outline assembly, Markdown export, and the `.writerblocks` reader.
Pure functions, no UI, no I/O, which is why it can be tested without Xcode.

`mac/App/Writerblocks/` is the SwiftUI app. `StoryDocument` is a `FileDocument`,
so Open, Save As, Duplicate, Rename, autosave, Versions and iCloud Drive all
come from the system rather than from storage code written by hand.

## Running the web prototype

```sh
npm install
npm run dev        # http://localhost:5173
```

```sh
npm test           # engine + deck unit tests
npm run build      # typecheck and static production build into dist/
npm run preview    # serve the production build on :4173
npm run test:e2e   # drive the previewed build through the whole loop in a browser
```

`npm run build` produces a plain static site — no server, no accounts, no
backend. Your work lives in the browser's local storage, and you can export it
to a file at any time.

## Using it

**Ask** is where you live. One question, one line, `Enter`. Two escape hatches,
because a tool about not getting stuck must never get you stuck:

- **Skip for now** steps the question aside. It comes back after a few more
  blocks — it is not thrown away.
- **Not sure yet** records the question with no answer. It shows up in the
  outline as an open thread, which is more useful than pretending you were never
  asked.

Naming something opens it up. Answer *Who is the main character?* with "Marla"
and a Marla column appears with two dozen questions of its own. The deck spreads
its attention across whatever you've named, so the web grows outward rather than
burrowing into whoever came first. If you'd rather go deep, **keep asking me
about** pins the questions to one subject.

**Board** is every block as a card, grouped in columns. Drag to reorder, drag
between columns, click any card to rewrite it, rename a column, add a character
or a place by hand. A block's column decides where it lands in the outline, so
moving a card moves it in the outline too.

**Outline** assembles everything: premise, then characters, then places, then
the shape of the story. Scenes sort into story order by their beat, so answering
the ending first still reads correctly. Copy it as Markdown, download it as
`.md`, or export the whole project as `.json` and import it back later.

## Rewriting the questions

The deck is content, not machinery. It lives in one file —
[`src/data/questions.ts`](src/data/questions.ts) — and it's meant to be edited.
Each entry is:

```ts
{
  id: 'char-vocation',
  strandType: 'character',
  text: 'What does {subject} do for a living?',   // {subject} becomes the name
  hint: 'Optional coaching, shown while answering but never stored',
  priority: 5,                                     // lower is asked earlier
  unlocks: ['char-likes-job'],                     // gated until this is answered
  spawns: 'character',                             // answering opens a new strand
  beat: 50,                                        // scene questions: story order
  repeatable: true,                                // can be asked more than once
}
```

The rules a good question follows: it's answerable in one sentence, and it's
concrete. "What is the theme?" produces a block. "What does she do when nobody
is watching?" produces a sentence.

`npm test` includes a set of integrity checks on the deck — unique ids, unlocks
that point at real questions, `{subject}` only where a strand has a real name —
so a bad edit fails there rather than halfway through a writing session.

## How it's built

React + TypeScript + Vite, one runtime dependency worth naming (`@dnd-kit` for
the board). The interesting part is `src/engine/`, which is pure functions with
no React in them:

| | |
| --- | --- |
| `deck.ts` | picks the next question — gating, skips, spreading attention across strands |
| `strands.ts` | every state change: answering, spawning, moving, editing |
| `outline.ts` | blocks → outline sections |
| `markdown.ts` | outline → exportable Markdown |

State changes are `(project, …) => project`, driven through a reducer in
`src/state/useProject.ts`. Saving is a debounced write in one effect, so the
reducer stays pure and testable.
