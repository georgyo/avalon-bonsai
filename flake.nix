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
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";

    # The opam repositories the local 5.2.0+ox switch uses, pinned as flake inputs so the
    # resolution is reproducible. Order = search priority: oxcaml dev, then oxcaml stable,
    # then upstream opam-repository (an overlay, not a full fork — leaf packages come from
    # upstream).
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    oxcaml-opam = {
      url = "github:oxcaml/opam-repository";
      flake = false;
    };
    oxcaml-opam-dev = {
      url = "github:oxcaml/opam-repository/dev";
      flake = false;
    };
    opam-nix.inputs.opam-repository.follows = "opam-repository";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      opam-nix,
      opam-repository,
      oxcaml-opam,
      oxcaml-opam-dev,
    }:
    # x86_64-linux is the verified system. aarch64-linux is declared but not yet
    # CI-verified (CI only builds x86_64-linux; a second cold OxCaml build would not fit
    # the GitHub Actions cache). darwin would need separate work — add systems here once
    # verified.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        on = opam-nix.lib.${system};

        repos = [
          oxcaml-opam-dev
          oxcaml-opam
          opam-repository
        ];

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

        # Resolving the query against the large oxcaml opam repo runs opam's solver for >60s,
        # which trips OPAMSOLVERTIMEOUT under `nix build` IFD on a slow CI runner. opam-nix
        # gives no way to raise that timeout, so instead we MATERIALIZE the resolution: run the
        # solver once locally and commit its output (package-defs.json). CI then reads that file
        # via materializedDefsToScope and never runs the solver at all. Regenerate with:
        #   ./scripts/update-package-defs.sh
        #
        # Only defined on x86_64-linux: evaluating it runs the opam solver via
        # import-from-derivation (exactly what materialization exists to avoid), and the
        # aarch64-linux variant cannot even build on an x86_64 host.
        materialize =
          if system == "x86_64-linux" then
            on.materialize {
              inherit repos;
              regenCommand = [ "./scripts/update-package-defs.sh" ];
            } query
          else
            null;

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

          # zarith's opam entry points at an unpinned git branch
          # (`git+https://github.com/avsm/zarith.git#oxcaml`), the one dependency that forced
          # `--impure`. Pin it to an explicit rev + hash so the build is pure and reproducible.
          # To update: bump the rev and refresh the hash with
          #   nix-prefetch-git --url https://github.com/avsm/zarith.git --rev <rev>
          zarith = prev.zarith.overrideAttrs (_: {
            src = pkgs.fetchgit {
              url = "https://github.com/avsm/zarith.git";
              rev = "50e84d371ee53e9ff62e4e7fbf17bcb903d2d846";
              hash = "sha256-+JLfOF+GCT9cfCDaIkqxMHvR0Fy6dX99F4bHIk4USn0=";
            };
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
        }
        # `./scripts/update-package-defs.sh` regenerates the committed resolution (e.g.
        # after bumping the opam repo inputs) by building this package and copying it to
        # package-defs.json (plus refreshing package-defs.lock). This is the only step
        # that runs opam's solver; the normal build never does. x86_64-linux only — see
        # the `materialize` binding above.
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          materialize = pkgs.runCommand "package-defs.json" { } "cp ${materialize} $out";
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
