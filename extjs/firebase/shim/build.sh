#!/usr/bin/env bash
# Build the vendored Firebase SDK bundle -> ../vendor/firebase-shim.js (commit the result).
#
# Pipeline (the local node_modules/.bin is prepended to PATH below, so direct invocation
# uses the pinned esbuild/babel from package-lock.json, never global versions):
#   1. esbuild bundles the modular SDK entry into one es2015 IIFE.
#   2. babel transpiles it to ES5 — js_of_ocaml's embedded-JS printer mangles ES2015
#      generators (function*/yield) into invalid strict-mode code, so the bundle that gets
#      baked into main.bc.js via (js_of_ocaml (javascript_files ...)) MUST be generator-free.
#   3. prepend regenerator-runtime, which defines the global babel's lowered generators call.
#   4. esbuild minifies the combined ES5 file.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$PWD/node_modules/.bin:$PATH"
mkdir -p .build
esbuild entry.mjs --bundle --format=iife --target=es2015 --outfile=.build/step1.js
babel --config-file ./.babelrc.json .build/step1.js -o .build/step2.js
cat node_modules/regenerator-runtime/runtime.js .build/step2.js > .build/step3.js
esbuild .build/step3.js --minify --outfile=../vendor/firebase-shim.js
echo "built firebase/vendor/firebase-shim.js ($(wc -c < ../vendor/firebase-shim.js) bytes)"
