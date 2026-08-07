# firebase/shim — vendored Firebase SDK bundle

`entry.mjs` imports the exact Firebase v12 modular functions the OCaml bindings in
`../firebase.ml` call and re-exports them on `globalThis.__fb`. The build produces
`../vendor/firebase-shim.js` (committed), which `../dune` embeds into `main.bc.js` via
`(js_of_ocaml (javascript_files ...))` — the same way the bonsai_web_components bindings ship
their JS. The result: the SDK is present synchronously at startup, with **no gstatic CDN and no
runtime `import()`** (`Firebase.on_ready` just snapshots `globalThis.__fb`).

## Rebuild

```sh
cd firebase/shim
npm install
npm run build        # -> ../vendor/firebase-shim.js  (commit the result)
```

Built with firebase 12.15.0, esbuild 0.28.1, @babel/preset-env 7.28.

## Why the build is more than `esbuild --bundle` (important)

js_of_ocaml parses and re-prints every file it embeds via `(javascript_files ...)`, and its
printer **mangles ES2015 generators** (`function*`/`yield`) into code that throws
`Unexpected strict mode reserved word` at runtime — the whole bundle then fails to load and the
page is blank. Firestore's realtime code is full of generators (esbuild also lowers `async` to
generators at its es2015 floor), so the embedded bundle must be **generator-free ES5**. esbuild
cannot target ES5, so `build.sh` does: esbuild bundle (es2015) → **babel → ES5** → prepend
`regenerator-runtime` (defines the global babel's lowered generators call) → esbuild minify.

This is the same shape as the Jane Street bindings' pre-babelled `for_ocaml_bindings.js`.

## When to rebuild

Whenever you change the import list in `entry.mjs` (i.e. you start calling a new free Firebase
function from `firebase.ml`) or bump the pinned `firebase` version in `package.json`. Methods on
handles (`user.getIdToken`, `snapshot.exists()`/`.data()`, the `onSnapshot` unsubscribe) need no
import.
