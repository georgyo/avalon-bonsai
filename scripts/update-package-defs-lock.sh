#!/usr/bin/env bash
# Regenerate package-defs.lock: the flake.lock revisions of the opam repo inputs that the
# committed package-defs.json resolution was materialized against.
#
# Normally run via scripts/update-package-defs.sh, which re-materializes
# package-defs.json and then calls this.
#
# CI re-runs this script and diffs the result against the committed file, so a flake
# update that forgets to re-materialize package-defs.json fails loudly. (CI runs only
# this script, not the wrapper: the whole point of materialization is that CI never
# runs the solver.)
#
# opam-nix's own provenance mechanism (`__opam_nix_repos` + `materializedDefsToScope
# { inherit repos; }`) would replace this, and package-defs.json does record it — but it
# compares Nix *store paths*, which differ between Determinate Nix (CI) and upstream Nix
# (local) for byte-identical inputs, so enabling it fails every CI build. See the `scope`
# binding in flake.nix. This script compares flake.lock revs instead, which is portable.
#
# REPOS must list the flake inputs used as opam repositories, i.e. exactly what the
# `repos` binding in flake.nix holds. Keep the two in sync: an input named here that
# flake.lock does not have is a hard error rather than a `null` line, because a stale
# name silently recording `null` is what this check is supposed to prevent.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOS=(opam-repository oxcaml-opam)

# Build the contents first and move them into place only on success: writing the loop
# straight into package-defs.lock would truncate the committed file before a missing
# input could abort the run.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for name in "${REPOS[@]}"; do
  rev=$(jq -r --arg n "$name" '.nodes[$n].locked.rev // empty' flake.lock)
  if [ -z "$rev" ]; then
    echo "$0: '$name' has no locked rev in flake.lock." >&2
    echo "  Update REPOS in this script to match the \`repos\` binding in flake.nix." >&2
    exit 1
  fi
  echo "$name $rev"
done > "$tmp"

mv "$tmp" package-defs.lock
trap - EXIT

echo "wrote package-defs.lock:"
cat package-defs.lock
