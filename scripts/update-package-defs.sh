#!/usr/bin/env bash
# Re-materialize the opam resolution after bumping the opam repo flake inputs: runs the
# opam solver (via `nix build .#materialize`, the only step that ever runs it), copies the
# result to the committed package-defs.json, and pins any git source it contains that
# names a branch rather than a commit (pure evaluation cannot fetch those). Nothing needs
# pinning today, so that step normally reports "nothing to pin"; it is there so an opam
# repo bump that reintroduces a branch source is handled instead of breaking the build.
# x86_64-linux only (see the `materialize` binding in flake.nix).
#
# There is no separate lock file to refresh: the materialized file records the repositories
# it was resolved against, and flake.nix checks them on every build, so a flake update
# without a re-materialization fails loudly at evaluation time.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(nix build .#materialize --no-link --print-out-paths)
cp "$out" package-defs.json
# The store output is read-only and pinning rewrites the file in place — copy first.
chmod u+w package-defs.json
nix run .#opam-nix-pin-git-refs -- package-defs.json
echo "wrote package-defs.json"
