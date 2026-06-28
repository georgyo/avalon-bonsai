# End-to-end tests

Playwright-driven multiplayer tests that exercise the full game against the **live**
backend (Firebase + the `https://avalon.onl/api` REST server).

## Files

- `serve.cjs` — serves `_build/default/bin` and reverse-proxies `/api` → `https://avalon.onl/api`
  (so the client talks to the real server same-origin, avoiding CORS).
- `play.cjs` — spawns 5 anonymous players, creates/joins a lobby, starts a game, and plays
  it to completion. Reads each player's secret role and either succeeds every mission
  (`MODE=good`) or has evil players sabotage (`MODE=evil`).

## Running

```sh
# build the optimized bundle
eval $(opam env --switch=5.2.0+ox)
dune build --profile release bin/main.bc.js

# 1. start the proxy/static server
node tests/e2e/serve.cjs        # listens on :8123

# 2. drive a game (uses Playwright's bundled Chromium; or set CHROME=/path/to/chrome)
PLAYWRIGHT=$(node -e "console.log(require.resolve('playwright'))") \
SHOTS_DIR=/tmp/avalon-e2e \
MODE=good \
node tests/e2e/play.cjs
```

Screenshots of the board / end-game are written to `SHOTS_DIR` (default `/tmp/avalon-e2e`).

## Notes

- These create real lobbies/games on the production server, so they have side effects.
- 5 contexts each load the JS bundle; use the `--profile release` build (≈1.7 MB) rather
  than the dev build (≈70 MB).
- Verified flows: happy-path game (Good wins + achievements), proposal rejection +
  re-proposal, and evil sabotage (Mission Failed rendering).
