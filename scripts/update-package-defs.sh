#!/usr/bin/env bash
# Re-materialize the opam resolution after bumping flake inputs: runs the opam solver
# (via `nix build .#materialize`, the only step that ever runs it), copies the result to
# the committed package-defs.json, and refreshes package-defs.lock so CI's staleness
# check passes. x86_64-linux only (see the `materialize` binding in flake.nix).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(nix build .#materialize --no-link --print-out-paths)
cp "$out" package-defs.json
chmod u+w package-defs.json
echo "wrote package-defs.json"
./scripts/update-package-defs-lock.sh
