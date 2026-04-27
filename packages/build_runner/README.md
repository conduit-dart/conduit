# conduit_build_runner

`package:build` builders that generate the runtime metadata Conduit
needs at AOT compile time. Replaces the `dart:mirrors`-based discovery
performed by `conduit build`.

## Status

| Phase (per [`docs/AOT_WITHOUT_BUILD.md`](../../docs/AOT_WITHOUT_BUILD.md)) | Builder | Shipped |
| --- | --- | --- |
| 0 | `StampBuilder` (no-op smoke test) | yes |
| 1 | `SerializableBuilder` | yes |
| 1 (this package) | `ChannelBuilder` | yes |
| 1 (this package) | `RegistryBuilder` (aggregator → `lib/conduit.g.dart` + `bootstrap()`) | yes |
| 2 | `ManagedObjectBuilder` | not yet |
| 3 | `ControllerBuilder` (Controller + ResourceController dispatch) | not yet |
| 5 | `ConfigurationBuilder` | not yet |

The pieces in place today let you AOT-compile a Conduit app whose only
runtime types are `ApplicationChannel`s and `Serializable`s. Apps with
controllers, ORM, or `Configuration` subclasses still need the
deferred builders before `dart compile exe` works end-to-end.

## Usage

In a Conduit application's `pubspec.yaml`:

```yaml
dev_dependencies:
  build_runner: ^2.14.1
  conduit_build_runner: ^6.0.0
```

In `bin/main.dart`:

```dart
import 'package:conduit_core/conduit_core.dart';
import 'package:my_app/conduit.g.dart' as conduit_runtime;
import 'package:my_app/my_channel.dart';

Future<void> main(List<String> args) async {
  conduit_runtime.bootstrap();   // installs RuntimeContext

  final app = Application<MyChannel>()..options.port = 8888;
  await app.start();
}
```

Then build:

```sh
dart run build_runner build
dart compile exe bin/main.dart -o build/server   # production
./build/server
```

`bootstrap()` calls `RuntimeContext.install(...)` with a registry built
from every `*.conduit.json` manifest the per-source builders emit
during `dart run build_runner build`. After that, `RuntimeContext.current`
returns the generated context and never falls through to the
mirror-based fallback — which is why `dart compile exe` succeeds.

## Dev/JIT execution

Code that is run with `dart run` or `dart bin/main.dart` (no AOT) and
that **doesn't** call `bootstrap()` will get a clear `StateError` when
something tries to read `RuntimeContext.current`. To restore the
legacy mirror-discovery behavior in dev, import the dev entrypoint and
call the helper once at the top of `main()`:

```dart
import 'package:conduit_runtime/dev.dart';

void main() {
  enableMirrorFallback();   // installs MirrorContext as the default
  // ...
}
```

The `dev.dart` entrypoint of each affected package
(`conduit_runtime`, `conduit_core`, `conduit_config`) re-exports the
mirror-based machinery (`Compiler`, `BuildContext`, `MirrorContext`,
…). The non-`dev` library entrypoints are `dart:mirrors`-free and safe
for AOT.
