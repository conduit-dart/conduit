# 6.0.0

- Initial scaffold (phase 0 of the general-ORM migration documented in
  `docs/GENERAL_ORM.md`).
- Defines the `Dialect` abstract interface and `DialectCapabilities`.
- No production code consumes this yet — phase 1 extracts the shared
  SQL builders out of `packages/postgresql/`.
