{
  description = "conduit — Dart HTTP server framework (Melos monorepo)";

  # Pinned to a tarball URL (not `github:`) so the flake resolves
  # without hitting api.github.com — a small but real concern from
  # behind corporate proxies or when CI runners share an IP.
  inputs.nixpkgs.url = "https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-24.11.tar.gz";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            buildInputs = [
              # Pure Dart toolchain (NOT Flutter — conduit is server-side Dart).
              pkgs.dart
              # Melos drives the cross-package scripts (bootstrap/analyze/test).
              # Present in nixpkgs 24.11; if it ever drops out, fall back to
              # `dart pub global activate melos` inside the shell.
              pkgs.melos
              # conduit_postgresql + core integration tests need a postgres
              # server (CI spins up postgres:18). `postgresql` provides the
              # server + client binaries (initdb, pg_ctl, psql) for local runs.
              pkgs.postgresql
            ];

            shellHook = ''
              echo "conduit dev shell — $(dart --version 2>&1)"
              echo "  melos: $(command -v melos >/dev/null 2>&1 && echo "on PATH ($(command -v melos))" || echo 'run: dart pub global activate melos')"
              echo "  postgres: $(postgres --version 2>&1 | head -1)"
            '';
          };
        });

      # Best-effort smoke check usable from CI / `nix flake check`.
      # Scope is honest: a *pure* package build of a Melos monorepo is not
      # practical (melos bootstrap + per-package `dart pub get` need network
      # and a writable PUB_CACHE, which a pure derivation forbids). We only
      # assert the toolchain materializes and Dart runs.
      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          dart-version = pkgs.runCommand "conduit-dart-version" { } ''
            ${pkgs.dart}/bin/dart --version 2>&1 | tee "$out"
          '';
        });
    };
}
