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

The **native macOS app is the product**, on `main`, built and tested in CI. It is
now the only implementation — the React web prototype has been removed.

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
  Strands.swift                    every mutation: answer, spawn, move, edit, link, retitle
  Webs.swift                       derived connections between characters
  Mentions.swift                   the "/" rule: token, candidates, insertion
  Outline.swift                    blocks → outline sections + stats
  Markdown.swift                   outline → exportable Markdown
  StoryFile.swift                  tolerant .writerblocks reader/writer
  Resources/questions.json         the 69 questions — content, meant to be edited
mac/Tests/WriterblocksCoreTests/   145 tests, incl. the prototype fixture
mac/App/project.yml                XcodeGen spec (no .pbxproj in the repo)
mac/App/Writerblocks/              SwiftUI app
  WriterblocksApp.swift            single Window, menu commands, NSApplicationDelegate
  RootView.swift                   Route + AppRouter + the crossfade
  StoryStore.swift                 open story, debounced autosave, save errors
  HomeView.swift                   logline question + 4-column story grid
  StoryView.swift                  Ask/Board/Web/Outline tabs, Home button, save indicator
  WebView.swift                    the character graph, drag to connect
  AskView.swift  BoardView.swift  OutlineDocumentView.swift  StoryLibrary.swift

.github/workflows/mac.yml          swift test + xcodebuild on macos-latest
```

Everything else in the repo is `README.md`, `CLAUDE.md` and `.gitignore`. There
is no Node toolchain any more.

## Commands

```sh
swift test --package-path mac          # 145 engine tests, no Xcode needed
cd mac/App && xcodegen generate        # writes Writerblocks.xcodeproj (gitignored)
open mac/App/Writerblocks.xcodeproj    # then ⌘R
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

**`mac.yml` only runs on pushes to `main` and one named branch**, so a push to a
new working branch runs nothing at all. It has `workflow_dispatch`, so dispatch
it against the branch instead (`mcp__github__actions_run_trigger`,
`method: run_workflow`, `ref: <branch>`) rather than editing the trigger list.
The `concurrency` group cancels the previous run for the same ref, so dispatch
once per push and read that run.

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

**Connections between characters are derived, never stored.** `Webs.edges`
recomputes them from block answers × character labels on every call, for the
same reason an outline section is derived: correcting a character's name
re-forms the web for free and there is no second copy to drift. The only stored
part is `Block.aboutStrandId`, which records who a two-person question was
*about* — and even that is never needed to render the block, because both names
are substituted into `prompt` when it is written. Do not add a `links` array.

**Mentions are scanned in `answer` only, never in `prompt`.** A prompt names its
own subject by construction, and a pair prompt names both, so scanning prompts
would have every block prove its own link. There is a comment saying so in
`Webs.edges`; it is the kind of thing a later "optimisation" reintroduces.

**A skip key carries the other person when there is one.** `Deck.skipKey` is the
tally key as well as the skip key, so a two-part key for a pair question would
make "what does Marla think of Howard?" count as having asked what she thinks of
everyone. The two-part form for ordinary questions is byte-identical to what it
always was — every story file on disk is full of those keys, and
`StoryLibrary.duplicated` splits on `::`.

**The tally reads the pair link off the block, not off the template.** Deleting a
character nulls `aboutStrandId` and leaves pair blocks behind with no other;
keyed off the block they match nothing, which is right.

**The question on screen is not re-dealt while it is still askable.**
`Deck.isStillDealable` guards the backstop in `AskView`. Naming a character from
the answer field adds a strand mid-sentence, and a fresh character's first
question outranks most of the deck — so an unconditional re-deal would swap the
question out from under a half-written answer. The question is stored on the
block at submit time and read back in the outline for ever, so that is data
corruption, not a wobble. A renamed subject counts as stale on purpose.

**The "/" menu inserts `Webs.matchable`, not the label.** A character named from
a whole answer has a label like "Marla Vance, who runs the yard…"; the menu shows
that and writes "Marla". Inserting the label would be bad prose *and* would not
be found again. The single trailing space is load-bearing too — without it the
next keystroke glues onto the name and the connection is never made.

**Pair templates are character templates**, so the ordinary candidate loop has to
skip them explicitly. Dealt from there they would carry no other and store
`{other}` unsubstituted on a block, to be read back in the outline for ever.

**Question text is stored on the block and read back in the outline.** Keep
coaching in `hint`, keep `text` under 70 characters. A deck-integrity test
enforces this and several other rules — unique ids, unlocks pointing at real
questions, `{subject}` only where a strand has a real name.

## The fixture — keep it, even though the prototype is gone

`mac/Tests/WriterblocksCoreTests/Fixtures/` holds a story generated by the web
prototype's own engine plus the Markdown that engine produced, and the Swift
port must still reproduce it character for character.

It was a cross-check between two implementations. It is now a record of
behaviour that was once independently agreed — which is *why* it is worth more
than the tests around it. It caught both data bugs listed above; hand-written
tests would have carried the same wrong assumptions into the assertions. There
is no longer a second implementation to regenerate it from, so if it ever has to
change, that is a decision to make deliberately and explain, not a file to
update until the build goes green.

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

1. **GitHub Pages needs turning off** in repo settings — only the owner can do
   this. Deleting `deploy.yml` stopped the deploy, but the Pages *source* is
   still "Deploy from a branch", and that pipeline runs independently of any
   workflow: it publishes the un-built repo root on every push. There is no
   `index.html` there any more, so the live URL now serves a 404 or a rendered
   README until Pages is set to **Disabled**.
2. **iCloud conflict detection** — offered, not built. The one case where doing
   nothing can silently cost the writer work. `NSFileVersion
   .unresolvedConflictVersionsOfItem(at:)`.
3. **Version snapshots** — offered, not built. `NSFileVersion.addOfItem` on save
   plus a minimal restore list.
4. **Board drag feel** — improved over three rounds; if a residual pause on drop
   remains, the next lever is replacing the system drag with a pointer-driven
   one, which costs hand-written auto-scroll and cross-column hit-testing.
5. **Un-drawing a mention is not possible.** A false positive — "Howard Street"
   connecting to Howard — can only be removed by editing the sentence. A
   suppression list would be stored state contradicting derived state, which is
   the trap `Webs` exists to avoid. Revisit only if it actually annoys someone.
6. **The web's two thresholds are guesses** — `Webs.minCharacters` (2) and
   `Webs.minBlocks` (15). The second is a feel judgement about when a graph
   stops being discouraging, and has never been tried on a real story.
