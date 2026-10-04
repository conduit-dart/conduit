{
  description = "conduit — Dart HTTP server framework (Melos monorepo)";

  # Pinned to a tarball URL (not `github:`) so the flake resolves
  # without hitting api.github.com — a small but real concern from
  # behind corporate proxies or when CI runners share an IP.
  #
  # Pinned to an exact nixpkgs-unstable commit: release channels lag the
  # Dart SDK floor (nixos-26.05 ships 3.11.4, nixos-24.11 shipped 3.5.4),
  # and a branch-head tarball silently moves. Bump the rev when the floor
  # moves; `checks.dart-sdk-floor` fails if the pinned Dart is too old.
  inputs.nixpkgs.url = "https://github.com/NixOS/nixpkgs/archive/c9fe7d12cd78d1adcd12dd15e24432dde5b155a0.tar.gz";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # The workspace SDK floor, read from the root pubspec so the flake
      # cannot drift from it (e.g. `sdk: ">=3.12.0 <4.0.0"` -> "3.12.0").
      sdkFloor = builtins.head (builtins.match ''.*sdk: ">=([0-9.]+)[^"]*".*''
        (builtins.readFile ./pubspec.yaml));
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
              # If it ever drops out of nixpkgs, fall back to
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
      # and a writable PUB_CACHE, which a pure derivation forbids). We
      # assert the toolchain materializes, Dart runs, and the pinned Dart
      # satisfies the workspace SDK floor.
      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          dart-version = pkgs.runCommand "conduit-dart-version" { } ''
            ${pkgs.dart}/bin/dart --version 2>&1 | tee "$out"
          '';
          dart-sdk-floor =
            if nixpkgs.lib.versionAtLeast pkgs.dart.version sdkFloor
            then pkgs.runCommand "conduit-dart-sdk-floor" { } ''
              echo "dart ${pkgs.dart.version} >= workspace floor ${sdkFloor}" | tee "$out"
            ''
            else throw "nixpkgs pins Dart ${pkgs.dart.version}, below the workspace SDK floor ${sdkFloor}; bump the nixpkgs rev in flake.nix";
        });
    };
}
