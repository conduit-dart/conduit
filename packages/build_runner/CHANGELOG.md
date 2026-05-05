## 6.0.0

 - **FIX**(core): tolerate per-builder failures in mirror DataModelCompiler ([#253](https://github.com/conduit-dart/conduit/issues/253)). ([ca31856a](https://github.com/conduit-dart/conduit/commit/ca31856a7609133ce3f5322cd220c7cf76dd1973))
 - **DOCS**: add REFACTOR_CONTEXT.md architecture snapshot ([#247](https://github.com/conduit-dart/conduit/issues/247)). ([e6248ca2](https://github.com/conduit-dart/conduit/commit/e6248ca2177c25ec93bbca9bf7dc3d94868f3c8f))

## 6.0.0

 - **FIX**(core): tolerate per-builder failures in mirror DataModelCompiler ([#253](https://github.com/conduit-dart/conduit/issues/253)). ([ca31856a](https://github.com/conduit-dart/conduit/commit/ca31856a7609133ce3f5322cd220c7cf76dd1973))

# 6.0.0

- Initial scaffold (phase 0 of the AOT-without-conduit-build migration).
- Ships a no-op `StampBuilder` that proves the `package:build` wiring.
- Real generators (Channel, Controller, ManagedObject, Serializable,
  Configuration) land in subsequent releases.
