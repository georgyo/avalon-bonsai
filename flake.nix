{
  description = "avalon-bonsai — OxCaml Bonsai web client (hermetic opam-nix build)";

  # OxCaml (ocaml-variants.5.2.0+ox) and the Jane Street Bonsai preview packages are not in
  # nixpkgs — they live only in github.com/oxcaml/opam-repository. So we build hermetically
  # with opam-nix, resolving against those opam repos (opam's real solver handles the
  # `{post}` patch-guard disjunctions that defeat dune's own package manager). The compiler
  # is built from source; expect a slow first build unless a binary cache is configured.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    opam-nix = {
      # A fork of tweag/opam-nix (branch `dev`) carrying four features this build needs,
      # each of which used to be an out-of-tree hack here: the opam2json conversions of a
      # query are batched into one derivation (fast materialization), `resolveArgs
      # .solver-timeout` raises OPAMSOLVERTIMEOUT, `materialize` records the repositories
      # it resolved against so `materializedDefsToScope` can reject a stale resolution,
      # and `opam-nix-pin-git-refs` pins the git sources of package-defs.json. flake.lock
      # pins the exact rev, so `dev` moving does not affect reproducibility.
      url = "github:georgyo/opam-nix/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";

    # The opam repositories the local 5.2.0+ox switch uses, pinned as flake inputs so the
    # resolution is reproducible. Order = search priority: oxcaml first, then upstream
    # opam-repository (oxcaml is an overlay, not a full fork — leaf packages come from
    # upstream). package-defs.json records this list, in order, and the build checks it —
    # see the `scope` binding.
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    oxcaml-opam = {
      url = "github:oxcaml/opam-repository/main";
      flake = false;
    };
    opam-nix.inputs.opam-repository.follows = "opam-repository";
  };

  nixConfig = {
    extra-substituters = [ "https://cache.fu.io" ];
    extra-trusted-public-keys = [
      "georgyo-1:2yY6X+H3y0xp9e94WQsjXlWNDX2ElWWrp5P89pQ9zPM="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      opam-nix,
      opam-repository,
      oxcaml-opam,
    }:
    # x86_64-linux is the verified system. aarch64-linux is declared but not yet
    # CI-verified (CI only builds x86_64-linux; a second cold OxCaml build would not fit
    # the GitHub Actions cache). darwin would need separate work — add systems here once
    # verified.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        on = opam-nix.lib.${system};

        # The opam repositories to resolve against, in search-priority order. Each entry
        # carries the flake input's NAME as well as its source, so the lock helper below
        # can look their revs up in flake.lock without a second, hand-maintained list of
        # names — keeping those two in sync by hand is what left a phantom
        # `oxcaml-opam-dev null` line in package-defs.lock after that input was dropped.
        opamRepos = [
          {
            name = "oxcaml-opam";
            src = oxcaml-opam;
          }
          {
            name = "opam-repository";
            src = opam-repository;
          }
        ];
        repos = map (r: r.src) opamRepos;

        # The OxCaml compiler plus every library the dune files reference. "*" lets opam pick
        # the matching preview versions from the oxcaml repos.
        query = {
          ocaml-variants = "5.2.0+ox";
          dune = "*";
          core = "*";
          bonsai = "*";
          bonsai_web = "*";
          bonsai_web_components = "*";
          virtual_dom = "*";
          js_of_ocaml = "*";
          js_of_ocaml-ppx = "*";
          js_of_ocaml-compiler = "*";
          ppx_jane = "*";
          ppx_css = "*";
          ppx_html = "*";
          ppx_inline_test = "*";
        };

        # Resolving the query against the large oxcaml opam repo runs opam's solver for
        # >60s, which trips opam's default 60s OPAMSOLVERTIMEOUT on a slow machine — hence
        # `resolveArgs.solver-timeout`. So we MATERIALIZE the resolution: run the solver
        # once locally and commit its output (package-defs.json). CI then reads that file
        # via materializedDefsToScope and never runs the solver at all. Regenerate with:
        #   nix run .#update-package-defs
        #
        # Only defined on x86_64-linux: evaluating it runs the opam solver via
        # import-from-derivation (exactly what materialization exists to avoid), and the
        # aarch64-linux variant cannot even build on an x86_64 host.
        materialize =
          if system == "x86_64-linux" then
            on.materialize {
              inherit repos;
              resolveArgs.solver-timeout = 300;
              # Recorded in package-defs.json as `__opam_nix_regen`, which is what
              # opam-nix's own `opam-nix-regen` runs and what its error messages quote.
              regenCommand = [
                "nix"
                "run"
                ".#update-package-defs"
              ];
            } query
          else
            null;

        # The regen helpers are flake apps rather than checked-in shell scripts: `nix run`
        # pins the tools they need (jq, git) instead of trusting whatever is on PATH, they
        # get shellcheck'd at build time by writeShellApplication, and `nix run
        # .#update-package-defs` is a stable name for `__opam_nix_regen` to point at.
        #
        # Both resolve the repo root with `git rev-parse` rather than $0: under `nix run`,
        # $0 is a store path, and the cwd is wherever the caller happened to be.
        cdRepoRoot = ''
          root=$(git rev-parse --show-toplevel)
          if [ ! -e "$root/flake.nix" ]; then
            echo "$0: $root does not look like the avalon-bonsai checkout" >&2
            exit 1
          fi
          cd "$root"
        '';

        # Records the flake.lock revs of the opam repos that the committed
        # package-defs.json was materialized against. CI re-runs this and diffs, so a
        # flake update that forgets to re-materialize fails loudly. (opam-nix records the
        # same provenance inside package-defs.json, but the check built on it is not
        # portable — see the `scope` binding below.)
        update-package-defs-lock = pkgs.writeShellApplication {
          name = "update-package-defs-lock";
          meta.description = "Record the opam repo revs package-defs.json was materialized against";
          runtimeInputs = [
            pkgs.jq
            pkgs.git
          ];
          text = ''
            ${cdRepoRoot}

            # Generated from `opamRepos` in flake.nix — never edit this list by hand.
            repos=(${lib.concatStringsSep " " (map (r: lib.escapeShellArg r.name) opamRepos)})

            # Build the contents first and move them into place only on success: writing
            # the loop straight into package-defs.lock would truncate the committed file
            # before a missing input could abort the run.
            tmp=$(mktemp)
            trap 'rm -f "$tmp"' EXIT

            for name in "''${repos[@]}"; do
              rev=$(jq -r --arg n "$name" '.nodes[$n].locked.rev // empty' flake.lock)
              if [ -z "$rev" ]; then
                echo "$0: '$name' has no locked rev in flake.lock." >&2
                exit 1
              fi
              echo "$name $rev"
            done > "$tmp"

            mv "$tmp" package-defs.lock
            trap - EXIT

            echo "wrote package-defs.lock:"
            cat package-defs.lock
          '';
        };

        # Re-materialize the opam resolution after bumping the opam repo flake inputs: runs
        # the solver (via `nix build .#materialize`, the only step that ever runs it),
        # copies the result over package-defs.json, pins any git source in it that names a
        # branch rather than a commit (pure evaluation cannot fetch those; nothing needs it
        # today, so it normally reports "nothing to pin"), then refreshes package-defs.lock.
        #
        # The order is load-bearing: the store output is read-only, so it has to be copied
        # before it can be pinned, and pinning has to happen before any `nix build
        # .#default`.
        update-package-defs = pkgs.writeShellApplication {
          name = "update-package-defs";
          meta.description = "Re-run the opam solver and rewrite package-defs.json (+ .lock)";
          runtimeInputs = [ pkgs.git ];
          text = ''
            ${cdRepoRoot}

            out=$(nix build .#materialize --no-link --print-out-paths)
            cp "$out" package-defs.json
            chmod u+w package-defs.json
            ${opam-nix.packages.${system}.opam-nix-pin-git-refs}/bin/opam-nix-pin-git-refs \
              package-defs.json
            echo "wrote package-defs.json"
            ${lib.getExe update-package-defs-lock}
          '';
        };

        # NOTE: the staleness check is deliberately NOT enabled — passing `repos` here
        # would make `materializedDefsToScope` compare them against the repositories
        # package-defs.json was materialized against (recorded in it as
        # `__opam_nix_repos`). It false-positives across Nix implementations: opam-nix
        # identifies a repository by its store path, and Determinate Nix (what CI installs,
        # `determinate: true`) resolves these two inputs to different store paths than
        # upstream Nix does locally, for byte-identical content — same `narHash` in
        # flake.lock, different `<hash>-source`. Enabling it turned every CI build into
        # "the materialized package definitions are stale" (run 30162609745). Re-enable
        # with `{ inherit repos; }` once opam-nix identifies repositories by something
        # implementation-independent. The file still records the identities; nothing reads
        # them. Staleness is guarded by package-defs.lock instead — see scripts/.
        scope = (on.materializedDefsToScope { } ./package-defs.json).overrideScope overlay;

        overlay = final: prev: {
          # The OxCaml compiler build assumes a couple of things the pure Nix sandbox lacks:
          #   - its Makefiles hardcode `SHELL = /usr/bin/env bash` (no /usr/bin/env in sandbox);
          #   - its `install` target shells out to `rsync` (not in the default stdenv).
          oxcaml-compiler = prev.oxcaml-compiler.overrideAttrs (oa: {
            nativeBuildInputs = (oa.nativeBuildInputs or [ ]) ++ [ pkgs.rsync ];
            postPatch = (oa.postPatch or "") + ''
              find . -name 'Makefile*' -type f \
                -exec sed -i 's@^SHELL *= */usr/bin/env bash@SHELL = bash@' {} +
            '';
          });
        };

        # Direct build inputs; opam-nix propagates each package's transitive deps, so the
        # whole closure (bonsai, incremental, ppxlib, …) ends up on OCAMLPATH.
        deps = with scope; [
          ocaml-variants
          dune
          core
          bonsai
          bonsai_web
          bonsai_web_components
          virtual_dom
          js_of_ocaml
          js_of_ocaml-ppx
          js_of_ocaml-compiler
          ppx_jane
          ppx_css
          ppx_html
          ppx_inline_test
        ];

        avalon-bonsai = pkgs.stdenv.mkDerivation {
          pname = "avalon-bonsai";
          version = "0.1.0";
          src = self;
          buildInputs = deps;

          buildPhase = ''
            runHook preBuild
            export HOME=$TMPDIR
            export DUNE_CACHE=disabled
            dune build --profile release bin/main.bc.js bin/index.html
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            dune runtest test
            runHook postCheck
          '';

          # The product is the static client bundle: the JS plus everything in web/
          # (index.html today — bin/index.html is copied from web/index.html by a dune
          # rule — and any assets added later).
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp _build/default/bin/main.bc.js $out/main.bc.js
            cp -r web/. $out/
            runHook postInstall
          '';
        };
      in
      {
        packages = {
          default = avalon-bonsai;
          avalon-bonsai = avalon-bonsai;

          # A git source whose fragment is a branch rather than an explicit sha1 cannot be
          # fetched in pure evaluation mode, which would defeat materialization. This
          # script rewrites any such source in package-defs.json to the commit it resolves
          # to. Nothing needs it as of the 5.2.0minus38 oxcaml repo (zarith, which used to,
          # now resolves to a tarball), so it is a no-op guard: `nix run
          # .#update-package-defs` runs it after every re-materialization and CI asserts
          # `--check`, so an opam repo bump that reintroduces a branch source is caught
          # instead of breaking the build. Re-exported from the locked opam-nix input so
          # the script and the library that reads its output are always the same rev.
          inherit (opam-nix.packages.${system}) opam-nix-pin-git-refs;
        }
        # `nix run .#update-package-defs` regenerates the committed resolution (e.g. after
        # bumping the opam repo inputs) by building this package, copying it to
        # package-defs.json and pinning its git sources. This is the only step that runs
        # opam's solver; the normal build never does. x86_64-linux only — see the
        # `materialize` binding above.
        // lib.optionalAttrs (system == "x86_64-linux") {
          materialize = pkgs.runCommand "package-defs.json" { } "cp ${materialize} $out";
        };

        # The maintenance commands, replacing what used to be scripts/*.sh.
        apps = {
          update-package-defs-lock = {
            type = "app";
            program = lib.getExe update-package-defs-lock;
            inherit (update-package-defs-lock) meta;
          };
        }
        # Regenerating needs `.#materialize`, which only exists on x86_64-linux.
        // lib.optionalAttrs (system == "x86_64-linux") {
          update-package-defs = {
            type = "app";
            program = lib.getExe update-package-defs;
            inherit (update-package-defs) meta;
          };
        };

        # `nix flake check` builds the bundle and runs the unit tests.
        checks.default = avalon-bonsai;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ avalon-bonsai ];
        };

        formatter = pkgs.nixfmt-tree;

      }
    );
}
