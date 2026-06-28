# Dune package management (OxCaml) — status

This project is built with an **opam switch** (`5.2.0+ox`), not dune's package
management. I attempted to add a dune-workspace per the official tutorial
([dune-package-management/oxcaml](https://dune.readthedocs.io/en/latest/tutorials/dune-package-management/oxcaml.html))
but `dune pkg lock` cannot resolve this project's dependencies. The attempted config
is preserved in [`dune-workspace.oxcaml-pkg.example`](../dune-workspace.oxcaml-pkg.example).

## How to build today (works)

```sh
opam switch 5.2.0+ox            # repos: ox-dev, ox, default
eval $(opam env --switch=5.2.0+ox)
dune build                      # app (bin/main.bc.js)
dune runtest                    # offline unit tests (test/)
dune build --profile release bin/main.bc.js
```

## Why `dune pkg lock` fails

The tutorial's `dune-workspace` is correct in form. The blocker is in how the
OxCaml opam-repository enforces its patched packages versus how dune's dependency
solver behaves:

- The oxcaml repo is an **overlay**, not a standalone fork — it still needs the
  upstream `opam-repository` for leaf packages (`angstrom`, `uri`, `uucp`, …).
- It ships a package **`oxcaml-patch-guards`** (pulled into any OxCaml switch) that
  adds, for every patchable package `X`, a `{post}` disjunction:
  `oxcaml-X {post} | oxcaml-X-patches {post}`.
  - `oxcaml-X` = "the patched `X` is **not** installed" (it `conflicts: [X]`).
  - `oxcaml-X-patches` = "installed" (it depends on the real `X.<ver>+ox`).
- **opam** treats `{post}` dependencies as deferred (they don't drive version
  selection), so it simply installs the real `+ox` variants (`zarith 1.14+ox`,
  `topkg 1.1.1+ox`, …) and never materializes a guard.
- **dune's solver** resolves the `{post}` disjunction eagerly and picks the
  `oxcaml-X` guard side. That guard then conflicts with the real `X` that our
  dependencies require (e.g. `bignum → zarith >= 1.12`, `fmt → topkg`), and the
  solver does not backtrack to the `-patches` side. Result:

  ```
  - zarith -> (problem)
      bignum v0.18~preview... requires >= 1.12
      oxcaml-zarith guard requires conflict with all versions
  ```

  The same happens for `topkg`, `uutf`, `spawn`, and would continue through
  `yojson`, `js_of_ocaml`, etc.

Explicitly depending on the `oxcaml-X-patches` markers (see the example file) does
**not** fix it — the solver still selects the guard side of the `oxcaml-patch-guards`
disjunction and reports the conflict rather than backtracking.

The tutorial's hello-world locks fine because it pulls **no** patched package. This
project (bonsai_web + js_of_ocaml + ppx_*) inevitably pulls several, so it trips the
guards.

## When to retry

Re-test after an upgrade to either:
- **dune** — if its package solver gains backtracking across `{post}` disjunctions
  (or a way to prefer the `-patches` side), or
- the **oxcaml opam-repository** — if it changes the patch-guard mechanism to one
  dune's solver can resolve.

To retry: rename `dune-workspace.oxcaml-pkg.example` → `dune-workspace`, add the
`(package …)` block (in that file's trailer) to `dune-project`, and run `dune pkg lock`.
