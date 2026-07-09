# Avalon — OxCaml Bonsai client

A port of the [avalon](../avalon) Vue 3 + Vuetify + Firebase **client** into an
[OxCaml](https://oxcaml.org) [Bonsai](https://github.com/janestreet/bonsai) web app
(client side only). It talks to the same real backend: Firebase Auth (anonymous +
email-link), Firestore real-time listeners, and the REST server at
`https://api.avalon.onl/api`.

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
temporal/    temporal_shim — vendored Temporal polyfill (core's jsoo timezone loader
             needs it on browsers without native Temporal, i.e. Safari/iOS)
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
the Firebase SDK is vendored (`firebase/vendor/firebase-shim.js`, an ES5 bundle built by
`firebase/shim/build.sh`) and embedded into `main.bc.js` via the js_of_ocaml
`javascript_files` stanza in `firebase/dune`, exposed as `globalThis.__fb`.

## Building with Nix

The flake builds the whole toolchain (OxCaml compiler + Jane Street packages) hermetically
via opam-nix:

```
nix build .#default   # hermetic client-bundle build; output in result/
nix develop           # dev shell with the toolchain
```

The opam solver's resolution is materialized into the committed `package-defs.json`. After
bumping flake inputs, regenerate it (this also refreshes `package-defs.lock`, the marker CI
uses to detect a flake update without a re-materialization):

```
./scripts/update-package-defs.sh
```

CI (`.github/workflows/nix.yml`) builds the flake, after fast drift checks (vendored
Firebase shim, `package-defs.lock`) and a `nix fmt` no-op check.

Notes on the flake:

- The nix devShell intentionally does **not** include `ocamlformat` or `ocaml-lsp`: they
  would require re-materializing the resolution with OxCaml-patched versions. Use the
  opam switch for those tools.
- `aarch64-linux` is declared in the flake but not built in CI — a second cold OxCaml
  build would not fit the 10 GB Actions cache. Use an arm runner plus a real binary cache
  (e.g. Cachix) if needed.

## Test

The pure game logic (`avalon_core`) is covered by inline tests:

```
dune runtest test     # or `dune runtest` for everything
```

## Run

The client is fully static and calls the Avalon REST server directly at
`https://api.avalon.onl/api` (no same-origin `/api` proxy needed), so any static file
server works:

```
node tests/e2e/serve.cjs   # serves _build/default/bin on :8123
```

Then open `http://localhost:8123/`. Anonymous login, the lobby list, and live stats work
directly against the production Firebase project, and `api.avalon.onl` serves CORS
headers for allowed origins (`ocaml.avalon.onl`, `avalon.onl`, `localhost`,
`127.0.0.1` — the nginx map in georgyo/nix-conf), so the lobby/game REST calls work from
localhost too. Serving from an origin outside that list gets no
`Access-Control-Allow-Origin` back and the authenticated calls are blocked.

## Deploy

Every push to `master` publishes the Nix-built release bundle to GitHub Pages at
**https://ocaml.avalon.onl** (the `deploy-pages` job in `.github/workflows/nix.yml`; the
custom domain is configured in the repo's Pages settings). The REST API at
`api.avalon.onl` allows that origin in its CORS config (see georgyo/nix-conf,
`hosts/hydra/containers/avalon/default.nix`).

## Notes

- Built with the cont Bonsai API; the imperative Firebase listeners push snapshots into a
  single `Bonsai.Expert.Var` that drives the whole UI.
- The Firebase v12 modular SDK is not fetched at runtime: a vendored ES5 bundle
  (`firebase/vendor/firebase-shim.js`, rebuilt with `firebase/shim/build.sh`) is embedded
  ahead of the OCaml code in `main.bc.js` and exposes its exports on `globalThis.__fb`;
  if that global is missing the app shows an error instead of hanging on a spinner (it
  indicates a broken build, not a blocked CDN).
- Icons use FontAwesome 6 + Material Design Icons web fonts (loaded via CDN in
  `index.html`) instead of Vuetify's bundled icon sets.
- The dev bundle is large and unminified; pass `--profile release` (e.g. `dune build
  --profile release bin/main.bc.js bin/index.html`) for an optimized build.
