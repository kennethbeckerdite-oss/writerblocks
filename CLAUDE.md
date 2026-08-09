# writerblocks — project notes for Claude

## What this is

A tool for getting unstuck. It asks one small, concrete question at a time; each
single-sentence answer becomes a **block**; blocks stack into **strands** (a
character, a place, the run of scenes) and assemble into a first outline the
writer can export.

The premise, from *Zen and the Art of Motorcycle Maintenance*: writer's block is
usually not an absence of material but the fear of having nothing to say, and
that fear grows with the size of the question. So the tool never asks a big one.

**There is no AI in this and there should not be.** Nothing calls a model. The
value is the question, not a machine's opinion about someone's story. Do not add
model calls without the owner asking for them.

## Where the project is

The **native macOS app is the product** and is on `main`, built and tested in CI.
The **React web app was a visual prototype**; it still exists and is still
deployed, but it is disposable and slated for removal.

- Every question flow works end to end: logline creates a story, crossfade to the
  story view, Ask / Board / Outline, autosave to a real `.writerblocks` file,
  Finder double-click, Markdown export.
- Verified on the owner's Mac. The board's drag-and-drop has been through three
  rounds of feel fixes and is "way better" but may still not be perfect.

## Layout

```
mac/Package.swift                  SwiftPM package — the engine
mac/Sources/WriterblocksCore/      pure logic, no UI, no I/O
  Models.swift                     Project, Strand, Block, QuestionTemplate
  Questions.swift                  loads questions.json, builds gating indexes
  Deck.swift                       nextQuestion: gating, skips, spreading attention
  Strands.swift                    every mutation: answer, spawn, move, edit
  Outline.swift                    blocks → outline sections + stats
  Markdown.swift                   outline → exportable Markdown
  StoryFile.swift                  tolerant .writerblocks reader/writer
  Resources/questions.json         the 62 questions — content, meant to be edited
mac/Tests/WriterblocksCoreTests/   75 tests, incl. a cross-implementation fixture
mac/App/project.yml                XcodeGen spec (no .pbxproj in the repo)
mac/App/Writerblocks/              SwiftUI app
  WriterblocksApp.swift            single Window, menu commands, NSApplicationDelegate
  RootView.swift                   Route + AppRouter + the crossfade
  StoryStore.swift                 open story, debounced autosave, save errors
  HomeView.swift                   logline question + 4-column story grid
  StoryView.swift                  Ask/Board/Outline tabs, Home button, save indicator
  AskView.swift  BoardView.swift  OutlineDocumentView.swift  StoryLibrary.swift

src/                               web prototype (React) — disposable
e2e/walkthrough.mjs                27-check browser walkthrough of the prototype
.github/workflows/mac.yml          swift test + xcodebuild on macos-latest
.github/workflows/deploy.yml       Pages deploy of the prototype, from main only
```

## Commands

```sh
swift test --package-path mac          # 75 engine tests, no Xcode needed
cd mac/App && xcodegen generate        # writes Writerblocks.xcodeproj (gitignored)
open mac/App/Writerblocks.xcodeproj    # then ⌘R

npm test                               # web prototype, 61 tests
npm run build && npm run preview       # then: npm run test:e2e
```

## How to verify work here — read this before editing Swift

**This container is Linux and cannot compile Swift.** `download.swift.org` is
blocked by the proxy, and `api.github.com` and `*.github.io` are blocked too.

The loop that works: **push, and read the result from the `mac.yml` run via the
GitHub MCP tools** (`mcp__github__actions_list`, `mcp__github__get_job_logs`). A
full round is 40–90 seconds. The Actions API responses are cached and can lag a
minute or two behind reality — a run that looks stuck is often already finished,
so re-check before concluding anything.

`mac.yml` has a `paths:` filter on `mac/**`, so changes outside `mac/` will not
re-run it. That is intended, not a fault.

**CI proves it compiles and the tests pass. It cannot tell you how anything
feels.** Visual and interaction judgements belong to the owner — say so rather
than claiming a UI change works.

**The container is not durable.** It was rolled back once mid-session and lost
uncommitted work. Only what is pushed is real; commit early.

## Invariants — these are load-bearing and easy to break silently

**A skipped question is suppressed for a fixed number of blocks (8), not sorted
behind everything else.** Every answer can spawn a new subject carrying two dozen
fresh questions, so *any* priority penalty, however large, gets outrun forever
and "skip for now" quietly becomes "never again". `Deck.skipCooldownBlocks`.
Tested; do not "simplify" it into a penalty.

**A gated follow-up opens only on a non-empty parent answer**, so answering "not
sure yet" to the vocation question does not then ask whether they like that job.

**A block's outline section is derived from the strand it sits on, never
stored** (`sectionForStrandType`). This is what makes dragging a card on the
board move it in the outline with nothing left to disagree. Do not add a
`section` field to `Block`.

**`StoryFile` decodes via `JSONSerialization` by hand, not synthesised
`Codable`.** Synthesised decoding throws on the first missing key and takes the
whole document with it. A story file is untrusted input; losing a hundred
sentences to one malformed block is not an acceptable trade.

**Do not test for `Bool` with `value is Bool` when reading JSON numbers.**
Foundation bridges `NSNumber(0)` and `NSNumber(1)` to `Bool` as well as `Int`, so
that guard silently discards every legitimate `0` and `1` — and the first scene
of every story is at `beat: 0`, the first block of every strand at `order: 0`.
This bug shipped once and reordered stories on open. Use the CoreFoundation type
check (`StoryFile.isBoolean`).

**Saving failures must be visible.** The prototype's one real bug was swallowing
write errors, so saving looked healthy while doing nothing. `StoryStore` surfaces
`saveError` and `StoryView` shows a banner. Never quietly discard a write error.

**The engine owns the board's off-by-one.** Dropping onto a card means "insert
before me", counting the column *as displayed* (including the dragged card),
while the insert happens with that card lifted out.
`Stories.moveBlock(toDisplayIndex:)` holds that adjustment, with tests. Do not
reimplement it in a view.

**Question text is stored on the block and read back in the outline.** Keep
coaching in `hint`, keep `text` under 70 characters. A deck-integrity test
enforces this and several other rules — unique ids, unlocks pointing at real
questions, `{subject}` only where a strand has a real name.

## The cross-implementation fixture

`mac/Tests/WriterblocksCoreTests/Fixtures/` holds a story generated by the *web
prototype's own engine* plus the Markdown that engine produced. The Swift port
must reproduce it character for character. This is what caught both data bugs
above; hand-written tests would have carried the same wrong assumptions. If the
prototype is removed, keep the fixture — it is the record of correct behaviour.

## Decisions already made, with reasons

**No `DocumentGroup`.** It binds one window to one document, and two windows
cannot crossfade, so the single-window design and `DocumentGroup` are mutually
exclusive. Given up: macOS Versions, automatic iCloud conflict resolution, the
standard Edited/Revert/Duplicate title-bar menu. The underlying capabilities are
reachable via `NSFileVersion`; only the system-provided UI is not.

**A story is a file you own** — `.writerblocks` JSON in `~/Documents/writerblocks`
by default, so Time Machine, iCloud Drive and git all work. New stories are
written there without a save panel: being asked "where shall I save this?" the
instant you have typed a logline breaks the flow the home screen exists to
protect.

**The home screen is the logline question.** No "New story" button — typing a
sentence *is* creating one, and the app lands on the second question with the
first already recorded. Deliberately not the Mac convention of launching into an
Open panel.

**Merge, do not squash.** The commit messages carry the reasoning above.

**XcodeGen over a committed `.pbxproj`**, which conflicts on every edit.

## Open items

1. **Pages source is still "Deploy from a branch"** and needs changing to
   *GitHub Actions* in repo settings — only the owner can do this. Evidence:
   GitHub's Jekyll pipeline runs on branch pushes, and it publishes the un-built
   repo root, so it serves a blank page and can win the race for the live URL.
2. **Removing the web app** — owner's call, gated on the Mac app genuinely
   replacing it. Would delete `src/`, `e2e/`, `index.html`, `vite.config.ts`,
   `package.json`, `deploy.yml`, and the prototype half of `README.md`.
3. **iCloud conflict detection** — offered, not built. The one case where doing
   nothing can silently cost the writer work. `NSFileVersion
   .unresolvedConflictVersionsOfItem(at:)`.
4. **Version snapshots** — offered, not built. `NSFileVersion.addOfItem` on save
   plus a minimal restore list.
5. **Board drag feel** — improved over three rounds; if a residual pause on drop
   remains, the next lever is replacing the system drag with a pointer-driven
   one, which costs hand-written auto-scroll and cross-column hit-testing.
6. **The deck exists twice** while the prototype lives — `questions.json` (Swift,
   authoritative) and `src/data/questions.ts` (web). Edits must go to both, or to
   the JSON only once the prototype is gone.
