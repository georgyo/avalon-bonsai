#!/usr/bin/env bash
# Regenerate package-defs.lock: the flake.lock revisions of the three opam repo inputs
# that the committed package-defs.json resolution was materialized against.
#
# Normally run via scripts/update-package-defs.sh, which re-materializes
# package-defs.json and then calls this.
#
# CI re-runs this script and diffs the result against the committed file, so a flake
# update that forgets to re-materialize package-defs.json fails loudly. (CI runs only
# this script, not the wrapper: the whole point of materialization is that CI never
# runs the solver.)
set -euo pipefail
cd "$(dirname "$0")/.."
jq -r '.nodes as $n
  | "opam-repository", "oxcaml-opam", "oxcaml-opam-dev"
  | "\(.) \($n[.].locked.rev)"' flake.lock > package-defs.lock
echo "wrote package-defs.lock:"
cat package-defs.lock
