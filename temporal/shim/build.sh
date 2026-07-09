#!/usr/bin/env bash
# Build the vendored Temporal polyfill bundle -> ../vendor/temporal-shim.js (commit the
# result). Same pipeline as firebase/shim/build.sh, for the same reason: the bundle is
# embedded into main.bc.js via (js_of_ocaml (javascript_files ...)), and js_of_ocaml's
# embedded-JS printer mangles ES2015 generators into invalid strict-mode code, so the
# output MUST be generator-free ES5.
#   1. esbuild bundles the polyfill entry into one es2015 IIFE.
#   2. babel transpiles it to ES5.
#   3. prepend regenerator-runtime (defines the global that babel's lowered generators use).
#   4. esbuild minifies the combined ES5 file.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$PWD/node_modules/.bin:$PATH"
mkdir -p .build
esbuild entry.mjs --bundle --format=iife --target=es2015 --outfile=.build/step1.js
babel --config-file ./.babelrc.json .build/step1.js -o .build/step2.js
cat node_modules/regenerator-runtime/runtime.js .build/step2.js > .build/step3.js
esbuild .build/step3.js --minify --outfile=../vendor/temporal-shim.js
echo "built temporal/vendor/temporal-shim.js ($(wc -c < ../vendor/temporal-shim.js) bytes)"
