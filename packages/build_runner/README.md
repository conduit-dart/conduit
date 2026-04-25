# conduit_build_runner

`package:build` builders that generate the runtime metadata Conduit
needs at AOT compile time. Replaces the `dart:mirrors`-based discovery
performed by `conduit build`.

This is **phase 0** of the migration documented in
[`docs/AOT_WITHOUT_BUILD.md`](../../docs/AOT_WITHOUT_BUILD.md): the
package exists, the `build_runner` wiring is in place, and a no-op
`StampBuilder` proves the codegen path runs end-to-end. The real
builders (Channel, Controller, ManagedObject, Serializable,
Configuration) land in later phases.

## Usage

In a Conduit application's `pubspec.yaml`:

```yaml
dev_dependencies:
  build_runner: ^2.14.1
  conduit_build_runner: ^6.0.0
```

Then run:

```sh
dart run build_runner build
```

At phase 0 this only emits `*.conduit.stamp.dart` files alongside each
input library. Useful for smoke-testing the wiring; not yet useful for
shipping a Conduit app without `conduit build`.
