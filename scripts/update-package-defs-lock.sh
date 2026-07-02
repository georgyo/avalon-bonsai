#!/usr/bin/env bash
# Regenerate package-defs.lock: the flake.lock revisions of the three opam repo inputs
# that the committed package-defs.json resolution was materialized against.
#
# Run this whenever those inputs are bumped, together with re-materializing:
#   nix build .#materialize && cp -L result package-defs.json
#   ./scripts/update-package-defs-lock.sh
#
# CI re-runs this script and diffs the result against the committed file, so a flake
# update that forgets to re-materialize package-defs.json fails loudly.
set -euo pipefail
cd "$(dirname "$0")/.."
jq -r '.nodes as $n
  | "opam-repository", "oxcaml-opam", "oxcaml-opam-dev"
  | "\(.) \($n[.].locked.rev)"' flake.lock > package-defs.lock
echo "wrote package-defs.lock:"
cat package-defs.lock
