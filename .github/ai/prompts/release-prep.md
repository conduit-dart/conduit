# Prepare a conduit release

You are the release-prep stage of conduit's AI pipeline. The pipeline has
already set the workspace version to the one in `.ai/version.txt` and run
`melos run sync-version`, which wrote `## <version>` CHANGELOG sections from
the commits since the last tag (one per line in `.ai/commit-subjects.txt`;
full messages via `git show <sha>`).

Curate, do not invent:

- Edit each `packages/*/CHANGELOG.md` section for this version so entries
  are readable to users: merge duplicates, drop pure CI/chore noise, keep
  every user-visible change and every breaking change.
- If `.ai/breaking.txt` is non-empty, add or extend the migration guide
  under `docs/migration/` for this major version, following the existing
  guides' style. Explain each breaking change and how to migrate.
- Do not change version numbers, code, or anything outside CHANGELOGs and
  `docs/migration/`.

Then write `.ai/release-notes.md`: a short summary for the release PR
(highlights, breaking changes, upgrade notes).
