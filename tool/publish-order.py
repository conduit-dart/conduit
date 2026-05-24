#!/usr/bin/env python3
"""Print non-private conduit workspace packages in pub.dev publish order.

`melos exec --order-dependents` builds its DAG from both `dependencies:`
and `dev_dependencies:` — and `conduit_core` dev-depends on
`conduit_test`, which runtime-depends on `conduit_core`. melos refuses
to run on that cycle, blocking the publish step. pub.dev only
validates runtime dependencies server-side, so the dev_dependency arm
of the cycle is irrelevant for ordering; this script does the
topological sort over runtime `dependencies:` only.

Output: TSV `<package_name>\t<package_path>`, one row per package,
ordered so every package's runtime conduit-workspace dependencies
appear before it. Exits non-zero if a real runtime cycle exists.
"""

from __future__ import annotations

import glob
import sys
from pathlib import Path

import yaml


def main() -> int:
    packages: dict[str, tuple[str, set[str]]] = {}

    for pubspec in sorted(glob.glob("packages/*/pubspec.yaml")):
        data = yaml.safe_load(Path(pubspec).read_text()) or {}
        if data.get("publish_to") == "none":
            continue
        name = data.get("name")
        if not name:
            continue
        deps = set((data.get("dependencies") or {}).keys())
        packages[name] = (str(Path(pubspec).parent), deps)

    members = set(packages)
    # Restrict each package's dep set to other workspace members; external
    # deps (analyzer, postgres, …) live on pub.dev already and never
    # constrain our publish order.
    for name, (path, deps) in packages.items():
        packages[name] = (path, deps & members)

    order: list[str] = []
    seen: set[str] = set()

    while True:
        next_ready = sorted(
            n for n, (_, d) in packages.items() if n not in seen and d <= seen
        )
        if not next_ready:
            break
        order.extend(next_ready)
        seen.update(next_ready)

    remaining = set(packages) - seen
    if remaining:
        print(
            "runtime-dependency cycle in workspace; cannot order publish:",
            file=sys.stderr,
        )
        for n in sorted(remaining):
            print(f"  {n} -> {sorted(packages[n][1] - seen)}", file=sys.stderr)
        return 1

    for n in order:
        print(f"{n}\t{packages[n][0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
