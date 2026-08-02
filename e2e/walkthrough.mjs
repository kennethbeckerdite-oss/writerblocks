/**
 * End-to-end walkthrough: drives the built app in a real browser through the
 * whole loop — ask, skip, board, drag, outline, export, reload, import.
 *
 *   npm run build && npm run preview &   # serves on :4173
 *   npm run test:e2e
 *
 * Screenshots land in e2e/shots/. Set BASE_URL or CHROMIUM_PATH to override.
 */
import { chromium } from 'playwright';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = process.env.BASE_URL ?? 'http://localhost:4173/';
const SHOTS = join(dirname(fileURLToPath(import.meta.url)), 'shots');
mkdirSync(SHOTS, { recursive: true });

/** Playwright's bundled build, a preinstalled one, or whatever the caller names. */
function findChromium() {
  const candidates = [
    process.env.CHROMIUM_PATH,
    ...(process.env.PLAYWRIGHT_BROWSERS_PATH
      ? [join(process.env.PLAYWRIGHT_BROWSERS_PATH, 'chromium', 'chrome-linux', 'chrome')]
      : []),
    '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  ].filter(Boolean);
  return candidates.find((p) => existsSync(p));
}

const log = [];
const ok = (m) => { log.push(`  PASS  ${m}`); };
const fail = (m) => { log.push(`  FAIL  ${m}`); process.exitCode = 1; };
const check = (cond, m) => (cond ? ok(m) : fail(m));

const executablePath = findChromium();
const browser = await chromium.launch(executablePath ? { executablePath } : {});
const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 }, permissions: ['clipboard-read', 'clipboard-write'] });
const page = await ctx.newPage();

const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

// Fail loudly if the app ever talks to the network — this tool is offline by design.
const external = [];
page.on('request', (r) => {
  const u = r.url();
  if (!u.startsWith(BASE) && !u.startsWith('data:') && !u.startsWith('blob:')) external.push(u);
});

const question = () => page.locator('.ask__question').innerText();
const answer = async (text) => {
  await page.fill('.ask__input', text);
  await page.click('.ask__form button[type=submit]');
  await page.waitForTimeout(120);
};

await page.goto(BASE);
await page.waitForSelector('.ask__question');

// ---- 1. the opening question -------------------------------------------------
check((await question()).includes('logline'), 'opens on the logline question');
await page.screenshot({ path: `${SHOTS}/1-ask-opening.png` });

// ---- 2. the first three answers spawn strands --------------------------------
await answer('A diver goes back for the wreck that killed her brother.');
check((await question()).includes('main character'), 'asks who the main character is');
await answer('Marla');
check((await question()).includes('take place'), 'asks where it takes place');
await answer('A harbour town in February');

const q4 = await question();
check(/Marla|harbour town/.test(q4), `moves on to a named subject: "${q4}"`);
await page.screenshot({ path: `${SHOTS}/2-ask-named.png` });

// ---- 3. skipping puts a question back, it is not lost ------------------------
const skipped = await question();
await page.click('button:has-text("Skip for now")');
await page.waitForTimeout(120);
check((await question()) !== skipped, 'skipping moves on to a different question');

// ---- 4. answer a run of questions, including one left open -------------------
for (const a of ['She never apologises.', 'She lies to people she likes.', 'She dives for salvage.']) {
  await answer(a);
}
await page.click('button:has-text("Not sure yet")');
await page.waitForTimeout(120);

// ---- 5. focus on one subject -------------------------------------------------
if (await page.locator('#focus').count()) {
  const value = await page.locator('#focus option').nth(1).getAttribute('value');
  // innerText is empty for <option>; it is not laid out.
  const label = (await page.locator('#focus option').nth(1).textContent()).trim();
  await page.selectOption('#focus', value);
  await page.waitForTimeout(150);
  // innerText comes back CSS-uppercased, so compare case-insensitively.
  const shown = await page.locator('.ask__strand').innerText();
  check(shown.toLowerCase() === label.toLowerCase(), `focusing pins questions to "${label}"`);
  await page.selectOption('#focus', '');
  await page.waitForTimeout(120);
}

const counter = await page.locator('.ask__count').innerText();
check(/\d+ blocks/.test(counter) && counter.includes('character'), `counter shows accumulation: "${counter}"`);

// ---- 6. the skipped question comes back around -------------------------------
let cameBack = false;
for (let i = 0; i < 40; i += 1) {
  if ((await question()) === skipped) { cameBack = true; break; }
  await answer(`answer ${i}`);
}
check(cameBack, 'the skipped question returns later in the deck');

// ---- 7. the board ------------------------------------------------------------
await page.click('.bar__view:has-text("Board")');
await page.waitForSelector('.column');

const columns = await page.locator('.column__title').allInnerTexts();
check(columns.includes('Marla'), `board shows a spawned character column (${columns.join(', ')})`);

// add a place by hand
await page.selectOption('.board__add select', 'setting');
await page.fill('.board__add input', 'The wheelhouse');
await page.click('.board__add button');
await page.waitForTimeout(150);
check((await page.locator('.column__title').allInnerTexts()).includes('The wheelhouse'), 'adds a place by hand');

// add a free block to it
const wheelhouse = page.locator('.column', { has: page.locator('.column__title', { hasText: 'The wheelhouse' }) });
await wheelhouse.locator('.column__add input').fill('The radio only picks up one station.');
await wheelhouse.locator('.column__add input').press('Enter');
await page.waitForTimeout(150);
check((await wheelhouse.locator('.card').count()) === 1, 'adds a free-form block to a column');

// inline edit a card
const firstCard = page.locator('.column').first().locator('.card').first();
const before = await firstCard.locator('.card__answer').innerText();
await firstCard.locator('.card__answer').click();
await firstCard.locator('.card__input').fill('A diver goes back for the wreck that took her brother.');
await firstCard.locator('.card__input').press('Enter');
await page.waitForTimeout(150);
const after = await firstCard.locator('.card__answer').innerText();
check(after !== before && after.includes('took her brother'), 'edits a block in place');

await page.screenshot({ path: `${SHOTS}/3-board.png` });

// ---- 8. drag a block from one column to another ------------------------------
const marlaCol = page.locator('.column', { has: page.locator('.column__title', { hasText: 'Marla' }) });
const marlaBefore = await marlaCol.locator('.card').count();
const wheelBefore = await wheelhouse.locator('.card').count();

const grip = marlaCol.locator('.card').first().locator('.card__grip');
const source = await grip.boundingBox();
const target = await wheelhouse.locator('.column__blocks').boundingBox();
await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2);
await page.mouse.down();
for (let i = 1; i <= 12; i += 1) {
  await page.mouse.move(
    source.x + ((target.x + target.width / 2 - source.x) * i) / 12,
    source.y + ((target.y + 24 - source.y) * i) / 12,
  );
  await page.waitForTimeout(25);
}
await page.mouse.up();
await page.waitForTimeout(300);

const marlaAfter = await marlaCol.locator('.card').count();
const wheelAfter = await wheelhouse.locator('.card').count();
check(
  marlaAfter === marlaBefore - 1 && wheelAfter === wheelBefore + 1,
  `drags a block between columns (Marla ${marlaBefore}→${marlaAfter}, wheelhouse ${wheelBefore}→${wheelAfter})`,
);

// ---- 9. the outline ----------------------------------------------------------
await page.click('.bar__view:has-text("Outline")');
await page.waitForSelector('.outline__doc');

const headings = await page.locator('.outline__doc h2').allInnerTexts();
check(headings[0] === 'Premise', `outline leads with the premise (${headings.join(' / ')})`);
check(headings.includes('Characters') && headings.includes('Places'), 'outline groups characters and places');
check((await page.locator('.outline__open').count()) > 0, 'outline shows the open thread honestly');

// the dragged block now appears under Places, not Characters
const placesText = await page.locator('.outline__doc h2:has-text("Places") ~ div').allInnerTexts();
check(placesText.join(' ').includes('radio'), 'the hand-written block appears under Places');

await page.screenshot({ path: `${SHOTS}/4-outline.png`, fullPage: true });

// ---- 10. copy as markdown ----------------------------------------------------
await page.click('button:has-text("Copy as Markdown")');
await page.waitForTimeout(250);
const clip = await page.evaluate(() => navigator.clipboard.readText());
check(clip.startsWith('# '), 'copies markdown to the clipboard');
check(clip.includes('## Premise') && clip.includes('### Marla'), 'markdown carries headings and character sub-headings');
check(clip.includes('**still open**'), 'markdown marks the open thread');

// ---- 11. export json ---------------------------------------------------------
const [download] = await Promise.all([
  page.waitForEvent('download'),
  page.click('button:has-text("Export .json")'),
]);
const jsonPath = join(SHOTS, 'exported.json');
await download.saveAs(jsonPath);
check((await download.suggestedFilename()).endsWith('.writerblocks.json'), 'exports a .writerblocks.json file');

// ---- 12. autosave survives a reload -----------------------------------------
const blocksBefore = await page.locator('.outline__doc li').count();
await page.reload();
await page.waitForSelector('.ask__question');
await page.click('.bar__view:has-text("Outline")');
await page.waitForSelector('.outline__doc');
const blocksAfter = await page.locator('.outline__doc li').count();
check(blocksAfter === blocksBefore && blocksAfter > 0, `autosave survives reload (${blocksBefore} → ${blocksAfter} lines)`);

// ---- 13. re-import the json as a second story --------------------------------
await page.setInputFiles('input[type=file]', jsonPath);
await page.waitForTimeout(400);
check(await page.locator('.bar__projects').count() > 0, 'importing adds a second story to the switcher');
const options = await page.locator('.bar__projects option').count();
check(options === 2, `story switcher lists both stories (${options})`);

// ---- 14. new story starts clean ---------------------------------------------
await page.click('button:has-text("New story")');
await page.waitForTimeout(250);
await page.click('.bar__view:has-text("Ask")');
await page.waitForSelector('.ask__question');
check((await question()).includes('logline'), 'a new story starts back at the logline');

// ---- 15. no network, no errors ----------------------------------------------
check(external.length === 0, `makes no external network requests (${external.length})`);
check(errors.length === 0, `no console or page errors (${errors.join(' | ') || 'none'})`);

console.log(log.join('\n'));
console.log(`\n${log.filter((l) => l.startsWith('  PASS')).length} passed, ${log.filter((l) => l.startsWith('  FAIL')).length} failed`);

await browser.close();
