# Avalon — OxCaml Bonsai client

A port of the [avalon](../avalon) Vue 3 + Vuetify + Firebase **client** into an
[OxCaml](https://oxcaml.org) [Bonsai](https://github.com/janestreet/bonsai) web app
(client side only). It talks to the same real backend: Firebase Auth (anonymous +
email-link), Firestore real-time listeners, and the `/api` REST server.

## Layout

```
src/core/    avalon_core — pure, JS-free game logic (util, types, avalonlib, game,
             analysis): roles, derived state, achievements. This is the unit-tested library.
src/         avalon — the js_of_ocaml / Bonsai client:
  ffi          low-level js_of_ocaml helpers (fetch, promises, window/location)
  parse        Firestore JS objects -> typed model
  api          REST client (POST /api/*)
  toast        imperative toast (replaces vue-toastification)
  state        reactive store: Model in a Bonsai.Expert.Var; Firebase listeners + actions
  style        co-located component CSS via ppx_css (replaces Vuetify's styles)
  view         all UI components in Vdom (replaces the Vuetify components)
firebase/    firebase — typed bindings to the Firebase v12 modular SDK
test/        avalon_tests — inline_test suites over avalon_core
bin/
  main.ml             entry point
  runtime_avalon.js   runtime stub for a primitive missing in the jsoo runtime
web/
  index.html          loads FontAwesome/MDI fonts, the global CSS, and the bundle
```

## Prerequisites

- opam switch `5.2.0+ox` (the OxCaml compiler) with `bonsai_web` installed:
  ```
  opam install bonsai_web
  ```

## Build

```
eval $(opam env --switch=5.2.0+ox)
dune build                 # everything, or:
dune build bin/main.bc.js  # just the client bundle
```

Outputs to `_build/default/bin/`: `index.html` and `main.bc.js`. The styles are injected
at runtime by ppx_css (no separate stylesheet) plus the small global block in `index.html`;
the Firebase SDK is loaded at runtime via a dynamic `import()`, not bundled.

## Test

The pure game logic (`avalon_core`) is covered by inline tests:

```
dune runtest test     # or `dune runtest` for everything
```

## Run

Serve the build directory behind a proxy that forwards `/api` to the Avalon REST server
(as the original Vite dev server does, proxying to `https://avalon.onl/api`). The repo
ships a tiny static-server-plus-proxy for exactly this:

```
node tests/e2e/serve.cjs   # serves _build/default/bin on :8123, proxies /api -> avalon.onl
```

Then open `http://localhost:8123/`. Anonymous login, the lobby list, and live stats work
directly against the production Firebase project; lobby/game actions go through the `/api`
proxy. (`python3 -m http.server` will serve the static files but cannot proxy `/api`.)

## Notes

- Built with the cont Bonsai API; the imperative Firebase listeners push snapshots into a
  single `Bonsai.Expert.Var` that drives the whole UI.
- The Firebase v12 modular SDK is fetched at startup via a dynamic `import()` (no bundler);
  if that load fails (CDN blocked, offline) the app shows a recoverable error rather than
  hanging on a spinner.
- Icons use FontAwesome 6 + Material Design Icons web fonts (loaded via CDN in
  `index.html`) instead of Vuetify's bundled icon sets.
- The dev bundle is large and unminified; pass `--profile release` (e.g. `dune build
  --profile release bin/main.bc.js bin/index.html`) for an optimized build.
</content>
</invoke>
