# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A port of the Vue 3 + Vuetify + Firebase Avalon game **client** (original at `../avalon`)
to an OxCaml [Bonsai](https://github.com/janestreet/bonsai) web app (cont API), compiled
with js_of_ocaml. It talks to the real production backend: Firebase Auth/Firestore and the
REST server at `https://api.avalon.onl/api`.

## Commands

Every dune command needs the OxCaml switch in the environment first:

```sh
eval $(opam env --switch=5.2.0+ox)

dune build                                              # everything
dune build --profile release bin/main.bc.js bin/index.html  # optimized bundle (~1.7 MB vs ~70 MB dev)
dune runtest test                                       # unit tests (inline_test over avalon_core)
dune fmt                                                # format (applies via promotion)
```

Output lands in `_build/default/bin/` (`index.html` + `main.bc.js`). The client is fully
static; serve that directory with anything (`node tests/e2e/serve.cjs` serves it on :8123).

Hermetic Nix build: `nix build .#default`; dev shell: `nix develop` (intentionally has no
ocamlformat/ocaml-lsp — use the opam switch for those). After bumping flake inputs,
re-materialize the opam resolution with `./scripts/update-package-defs.sh` (CI fails on
drift otherwise).

E2E tests (Playwright, hit the live production backend — they create real
lobbies/games): see `tests/e2e/README.md`. They need the release bundle.

Deployment: every push to `master` publishes the Nix-built bundle to GitHub Pages at
`https://ocaml.avalon.onl` (the `deploy-pages` job in `.github/workflows/nix.yml`).

## Hard build rules

- **Warning 70 is a hard error everywhere** (`-w +70 -warn-error +70` in every dune file):
  every new `.ml` module must have a matching `.mli`.
- **The `firebase/` library is deliberately Core-free** (Stdlib only, `js_of_ocaml` its
  only dependency). `open! Core` would shadow its `Error` module. Watch the Stdlib
  differences: `List.map f list` argument order, no `String.is_empty`.
- The vendored Firebase bundle `firebase/vendor/firebase-shim.js` is committed and CI
  verifies it: after any change under `firebase/shim/`, run `cd firebase/shim && npm ci &&
  npm run build` and commit the result (comment-only `entry.mjs` changes are a no-op —
  esbuild strips comments — but rebuild anyway to be sure).
- `dune fmt` reflows files via promotion — accept its output. It skips
  `src/components/ui.mli` (pre-existing ocamlformat warning 50); that's known.
- The release jsoo build prints a benign `caml_array_create_float` missing-primitive
  warning; ignore it.

## Architecture

Five dune units, layered bottom-up:

- `firebase/` — typed bindings to the Firebase v12 **modular** SDK, one file per upstream
  module (`app`, `auth`, `firestore`, `error`), mirroring the upstream API shapes; mli docs
  quote the upstream reference. `firebase.ml` is the wrapped library's main module and the
  only external surface — it re-exports the submodules and hides `internal.ml` (shared
  js_of_ocaml plumbing). Cross-module abstract-type converters (`App.to_any`,
  `Error.of_any`) exist but are hidden from odoc with `(**/**)`. The SDK itself is not
  fetched at runtime: an ES5 bundle built by `firebase/shim/build.sh` is embedded into the
  executable via the `javascript_files` stanza and exposes its exports on
  `globalThis.__fb`.
- `src/core/` (`avalon_core`) — pure, JS-free game logic (roles, derived game state,
  achievements). This is the only unit-tested layer (`test/`).
- `src/` (`avalon`) — the client runtime, **unwrapped** library so components refer to
  `State`, `Api`, etc. by bare name: `ffi` (fetch/promise/window helpers), `parse`
  (Firestore JS objects → typed model), `api` (REST client), `state` (the reactive store),
  `toast`, `email_auth`.
- `src/components/` (`avalon_components`) — all UI as Vdom, using `ppx_css` (co-located
  styles, no stylesheet files) and `ppx_html`. Replaces Vuetify by hand-rolled components
  in `ui.ml`.
- `bin/` — entry point; jsoo compiled with `--effects cps`; `runtime_avalon.js` stubs a
  missing jsoo primitive.

Data flow: `State.init` initializes Firebase once (app/auth/firestore handles live in a
`services` ref inside `state.ml`; access via `State.auth ()` etc., which raise before
init). Firestore `on_snapshot` listeners push into a single `Bonsai.Expert.Var` holding
the whole `Model`; the entire UI derives from that var. User actions call `Api.*`, which
POST to `https://api.avalon.onl/api/<endpoint>` with a Firebase ID token in
`X-Avalon-Auth` — `Api` and `Email_auth` take `~auth:Firebase.Auth.t` explicitly (they
cannot read from `State`: state depends on api, not the reverse).

**CORS**: `api.avalon.onl` answers preflights and reflects allowed origins only
(`ocaml.avalon.onl`, `avalon.onl`, `localhost`, `127.0.0.1` — the nginx map in
georgyo/nix-conf `hosts/hydra/containers/avalon/default.nix`), and its allow-headers
include `X-Avalon-Auth`. So the API works from local serving and the production Pages
site alike; an origin outside that list gets its calls blocked by the browser.

The Firebase web API key in `src/state.ml` is public by design (standard for Firebase web
apps), not a leaked secret.
