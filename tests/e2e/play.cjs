// End-to-end multiplayer driver for the Avalon Bonsai client.
//
// Spawns 5 headless browser contexts, logs each in anonymously, creates/joins a lobby on
// the live backend (the client POSTs straight to https://api.avalon.onl/api; serve.cjs
// only serves the static bundle), starts a game, and plays it to completion. It reads each
// player's secret role from the role sheet and:
//   MODE=good (default) -> everyone succeeds missions  -> Good wins
//   MODE=evil           -> evil players sabotage       -> typically Evil wins
//
// Usage:
//   node tests/e2e/serve.cjs &              # in one terminal (serves _build/default/bin)
//   PLAYWRIGHT=/path/to/playwright \
//   CHROME=/path/to/chrome \
//   MODE=good node tests/e2e/play.cjs
//
// PLAYWRIGHT defaults to the playwright package resolvable from cwd; CHROME, if unset,
// uses Playwright's bundled browser.

const PW = process.env.PLAYWRIGHT || 'playwright';
const { chromium } = require(PW);
const CHROME = process.env.CHROME || undefined;
const URL = process.env.URL || 'http://localhost:8123/index.html';
const MODE = process.env.MODE || 'good';
const SHOTS = process.env.SHOTS_DIR || '/tmp/avalon-e2e';
const NAMES = ['ALICE', 'BOB', 'CARL', 'DAVE', 'EVE'];

const sleep = ms => new Promise(r => setTimeout(r, ms));
const log = (...a) => console.log(`[${new Date().toISOString().slice(11, 19)}]`, ...a);
const team = {};
let evilNames = [];

async function vis(loc) { try { return (await loc.count()) > 0 && await loc.first().isVisible(); } catch { return false; } }
async function click(loc) {
  try {
    if ((await loc.count()) && await loc.first().isVisible() && await loc.first().isEnabled()) {
      await loc.first().click({ timeout: 5000 });
      return true;
    }
  } catch { /* element raced away / disabled; ignore */ }
  return false;
}

async function loginAnon(page) {
  await page.goto(URL, { waitUntil: 'load' }); await sleep(3500);
  await click(page.getByText('Anonymous', { exact: true })); await sleep(400);
  await click(page.getByText('Login', { exact: true })); await sleep(4000);
}

async function readRoleOrDismiss(page, i) {
  const vr = page.locator('button:has-text("View Role")');
  if (await vis(vr)) {
    await click(vr); await sleep(700);
    const txt = await page.locator('.bottom-sheet').first().textContent().catch(() => '');
    const m = txt && txt.match(/on the (good|evil) team/);
    if (m && !team[NAMES[i]]) { team[NAMES[i]] = m[1]; log(`${NAMES[i]} = ${m[1]}`); }
    await page.mouse.click(640, 22); await sleep(300);
    return true;
  }
  const close = page.locator('button:has-text("Close")');
  if (await vis(close) && !(await vis(page.locator('text=/wins!|Game Canceled/')))) { await click(close); await sleep(300); return true; }
  return false;
}

async function checkPlayer(page, name) {
  const cb = page.locator('.v-list-item', { hasText: name }).first().locator('input[type="checkbox"]:not([disabled])').first();
  try { if ((await cb.count()) && !(await cb.isChecked())) await cb.click({ timeout: 4000 }); } catch {}
}

async function act(page, i) {
  if (await vis(page.locator('button:has-text("Propose Team")'))) {
    const t = await page.locator('text=/Propose a team of/').first().textContent().catch(() => '');
    const mm = t && t.match(/of\s+(\d+)/); const size = mm ? parseInt(mm[1]) : 2;
    const order = MODE === 'evil' ? [...evilNames, ...NAMES.filter(n => !evilNames.includes(n))] : NAMES;
    let picked = 0;
    for (const name of order) { if (picked >= size) break; await checkPlayer(page, name); picked++; await sleep(150); }
    await sleep(300);
    if (await click(page.locator('button:has-text("Propose Team")'))) return 'proposed';
    return null;
  }
  if (await click(page.locator('button:has-text("Approve")'))) return 'approved';
  if (await vis(page.locator('button:has-text("SUCCESS")'))) {
    if (MODE === 'evil' && team[NAMES[i]] === 'evil') { if (await click(page.locator('button:has-text("FAIL")'))) return 'FAIL'; }
    if (await click(page.locator('button:has-text("SUCCESS")'))) return 'success';
  }
  if (await click(page.locator('button:has-text("Assassinate")'))) return 'assassinated';
  if (await vis(page.locator('button:has-text("Select target")'))) {
    const cbs = page.locator('.v-list input[type="checkbox"]:not([disabled])');
    if (await cbs.count()) { try { await cbs.first().click({ timeout: 4000 }); } catch {} return 'picked-target'; }
  }
  return null;
}

(async () => {
  const fs = require('fs'); fs.mkdirSync(SHOTS, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    executablePath: CHROME,
  });
  const pages = []; const errs = [];
  for (let i = 0; i < 5; i++) { const ctx = await browser.newContext(); const p = await ctx.newPage(); p.on('pageerror', e => errs.push(`[${NAMES[i]}] ${e.message}`)); pages.push(p); }
  for (let i = 0; i < 5; i++) { await loginAnon(pages[i]); log(`${NAMES[i]} logged in`); }

  await pages[0].locator('input[placeholder="Your Name"]').fill(NAMES[0]); await sleep(300);
  await click(pages[0].getByText('Create Lobby', { exact: true })); await sleep(6000);
  const code = (await pages[0].locator('.lobby-name').first().textContent()).trim();
  log('lobby', code);
  for (let i = 1; i < 5; i++) {
    await pages[i].locator('input[placeholder="Your Name"]').fill(NAMES[i]); await sleep(300);
    await click(pages[i].getByText('Join Lobby', { exact: true })); await sleep(500);
    await pages[i].locator('input[placeholder="Lobby"]').fill(code); await sleep(300);
    await click(pages[i].getByText('Join Lobby', { exact: true })); await sleep(3500); log(`${NAMES[i]} joined`);
  }
  await sleep(1500);
  await click(pages[0].locator('button:has-text("Start Game")')); log('game started'); await sleep(5000);
  for (let i = 0; i < 5; i++) await readRoleOrDismiss(pages[i], i);
  evilNames = NAMES.filter(n => team[n] === 'evil');
  log('evil:', evilNames.join(', ') || '(unknown)');

  let ended = false;
  for (let tick = 0; tick < 80 && !ended; tick++) {
    for (let i = 0; i < 5; i++) {
      const p = pages[i];
      if (await vis(p.locator('text=/wins!|Game Canceled/'))) {
        ended = true;
        await p.screenshot({ path: `${SHOTS}/endgame.png`, fullPage: true }).catch(() => {});
        log('ENDGAME: ' + (await p.locator('text=/wins!|Game Canceled/').first().textContent()));
        break;
      }
      if (await readRoleOrDismiss(p, i)) continue;
      const a = await act(p, i); if (a) log(`${NAMES[i]}: ${a}`);
    }
    await sleep(1500);
  }
  if (!ended) log('did NOT reach endgame within budget');
  log('pageerrors: ' + (errs.length ? '\n' + errs.join('\n') : 'none'));
  await browser.close();
  process.exit(ended && errs.length === 0 ? 0 : 1);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
