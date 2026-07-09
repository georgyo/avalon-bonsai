// Entry point for the vendored Temporal polyfill bundle.
//
// core's js_of_ocaml timezone loader (core/timezone_js_loader_stubs.js) drives the JS
// Temporal API to compute timezone transitions; when the browser has no native
// globalThis.Temporal (Safari, as of 2026) it falls back to
// globalThis.TemporalPolyfill.Temporal, which the app must provide. Without it, the
// first Timezone.local lookup (forced during Bonsai startup via the TZ env variable
// that core's timezone_runtime.js sets from Intl) raises "unknown zone" and the app
// dies before mounting anything.
//
// The built artifact (../vendor/temporal-shim.js) is embedded into main.bc.js via
// `(js_of_ocaml (javascript_files ...))` in ../dune. Rebuild after changing this file:
// `npm ci && npm run build`.
import { Temporal } from "temporal-polyfill";

globalThis.TemporalPolyfill = { Temporal };
