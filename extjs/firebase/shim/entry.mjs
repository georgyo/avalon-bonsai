// Entry point for the vendored Firebase v12 modular SDK bundle.
//
// esbuild bundles exactly these imports (plus their transitive deps) into one minified IIFE
// and we expose them on globalThis.__fb, which the js_of_ocaml bindings (../app.ml,
// ../auth.ml, ../firestore.ml) dispatch through (see `call`/`on_ready` in ../internal.ml).
// The built artifact (../vendor/firebase-shim.js) is embedded directly into main.bc.js via
// `(js_of_ocaml (javascript_files ...))` in ../dune, so the SDK is present synchronously at
// startup — no gstatic CDN, no runtime `import()`.
//
// Keep this list in sync with the free functions the binding modules pass to `call`. Methods
// on handles (e.g. user.getIdToken, snapshot.exists/data) need no import. Rebuild after
// changing it: `npm install && npm run build`.
import { initializeApp } from "firebase/app";
import {
  initializeAuth,
  indexedDBLocalPersistence,
  browserLocalPersistence,
  onAuthStateChanged,
  signInAnonymously,
  signInWithEmailLink,
  sendSignInLinkToEmail,
  signOut,
} from "firebase/auth";
import { getFirestore, doc, onSnapshot, getDoc } from "firebase/firestore";

// The app only uses anonymous + email-link sign-in, so use initializeAuth with
// popupRedirectResolver undefined instead of getAuth: tree-shakes the popup/redirect
// and reCAPTCHA machinery out of the bundle. Exposed under the name "getAuth" with
// the same (app) -> Auth signature so the OCaml bindings need no changes; lazily
// initializes once per app and returns the cached instance thereafter.
const authByApp = new Map();
function getAuth(app) {
  let auth = authByApp.get(app);
  if (auth === undefined) {
    auth = initializeAuth(app, {
      persistence: [indexedDBLocalPersistence, browserLocalPersistence],
      popupRedirectResolver: undefined,
    });
    authByApp.set(app, auth);
  }
  return auth;
}

globalThis.__fb = {
  initializeApp,
  getAuth,
  onAuthStateChanged,
  signInAnonymously,
  signInWithEmailLink,
  sendSignInLinkToEmail,
  signOut,
  getFirestore,
  doc,
  onSnapshot,
  getDoc,
};
