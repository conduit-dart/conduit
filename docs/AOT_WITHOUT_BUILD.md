# AOT compilation without `conduit build`

> Status: design proposal, no code yet. Companion to
> [REFACTOR_CONTEXT.md](REFACTOR_CONTEXT.md). Once a direction is agreed
> this becomes the spec for the implementation PRs.

## 1. Goal

Today, shipping a Conduit app to production requires `conduit build`. That
command runs a custom AOT pipeline (`packages/runtime/lib/src/build.dart`)
which:

1. uses `dart:mirrors` to discover every `Compiler` subclass in the
   workspace,
2. lets each compiler emit Dart source for its runtime objects,
3. copies framework packages into a build directory and rewrites their
   pubspecs to remove `dart:mirrors` imports ("deflection"),
4. writes a generated `generated_runtime/` package wiring all runtimes
   into a `GeneratedContext`,
5. runs the AOT toolchain on the result.

We want a user to be able to write a Conduit app and just run

```sh
dart run build_runner build
dart compile exe bin/server.dart
```

with no Conduit-specific build command. The published packages should
work with the standard Dart toolchain.

## 2. Why this matters

- `conduit build` is custom infrastructure. It maintains its own
  copy-and-deflect pipeline ([packages/runtime/lib/src/build.dart](../packages/runtime/lib/src/build.dart),
  [packages/runtime/lib/src/generator.dart](../packages/runtime/lib/src/generator.dart),
  [packages/core/lib/src/runtime/compiler.dart:54-152](../packages/core/lib/src/runtime/compiler.dart)),
  which is one of the largest sources of complexity in the codebase
  (REFACTOR_CONTEXT §6 #2, #5, #11).
- Users on standard Dart tooling (CI runners, IDE build steps,
  `dart_dev`, IDE plugins, scripts that call `dart compile`) don't get
  Conduit support unless they invoke our custom CLI.
- The "deflection" step rewrites pubspecs of *our own* packages at build
  time — it works, but it's brittle, uses hard-coded package names
  ([packages/core/lib/src/runtime/compiler.dart:96-120](../packages/core/lib/src/runtime/compiler.dart)),
  and breaks when Dart's package layout assumptions change.
- The custom code generator uses string-token replacement
  ([packages/runtime/lib/src/generator.dart](../packages/runtime/lib/src/generator.dart)).
  Standard Dart codegen uses `package:build` + `package:source_gen`, with
  AST-based code building and incremental rebuilds.

## 3. Where mirrors are actually used

Surveyed via `grep -r "import 'dart:mirrors'"` over `packages/`. Two
distinct categories:

### 3.1 Build-time only (runs inside `conduit build`)

These can be rewritten as `package:build` `Builder`s. None of them ship
to the user's runtime today — they only run during `conduit build`.

| File | Job |
| --- | --- |
| [packages/runtime/lib/src/mirror_context.dart](../packages/runtime/lib/src/mirror_context.dart) | discover all `Compiler` subclasses across the loaded mirror system |
| [packages/runtime/lib/src/build.dart](../packages/runtime/lib/src/build.dart) | drive the pipeline |
| [packages/runtime/lib/src/build_context.dart](../packages/runtime/lib/src/build_context.dart) | per-build state |
| [packages/core/lib/src/runtime/compiler.dart](../packages/core/lib/src/runtime/compiler.dart) | enumerate channel/controller/serializable/managed-object subclasses, emit a runtime per type |
| [packages/core/lib/src/runtime/orm/data_model_compiler.dart](../packages/core/lib/src/runtime/orm/data_model_compiler.dart) | walk `ManagedObject` subclasses |
| [packages/core/lib/src/runtime/orm/entity_builder.dart](../packages/core/lib/src/runtime/orm/entity_builder.dart) | parse a table definition class, build the entity descriptor |
| [packages/core/lib/src/runtime/orm/entity_mirrors.dart](../packages/core/lib/src/runtime/orm/entity_mirrors.dart) | mirror helpers used by `entity_builder` |
| [packages/core/lib/src/runtime/orm/property_builder.dart](../packages/core/lib/src/runtime/orm/property_builder.dart) | build `ManagedAttributeDescription` / `ManagedRelationshipDescription` |
| [packages/core/lib/src/runtime/orm/validator_builder.dart](../packages/core/lib/src/runtime/orm/validator_builder.dart) | extract `@Validate` metadata |
| [packages/core/lib/src/runtime/resource_controller_generator.dart](../packages/core/lib/src/runtime/resource_controller_generator.dart) | emit operation dispatcher source |
| [packages/core/lib/src/runtime/resource_controller_impl.dart](../packages/core/lib/src/runtime/resource_controller_impl.dart) | parameter binding metadata |
| [packages/core/lib/src/runtime/resource_controller/utility.dart](../packages/core/lib/src/runtime/resource_controller/utility.dart), [documenter.dart](../packages/core/lib/src/runtime/resource_controller/documenter.dart) | helpers used by the above |
| [packages/config/lib/src/compiler.dart](../packages/config/lib/src/compiler.dart), [mirror_property.dart](../packages/config/lib/src/mirror_property.dart), [runtime.dart](../packages/config/lib/src/runtime.dart) | reflect on `Configuration` fields |
| [packages/core/lib/src/utilities/mirror_helpers.dart](../packages/core/lib/src/utilities/mirror_helpers.dart) | reflection utilities |

### 3.2 Dev-mode runtime (mirrors used in the *running* app)

This is the harder set. When a Conduit app runs *without* having been
through `conduit build`, the framework today falls back to mirror-based
runtime impls. These have to either go away or be replaced by code
that's emitted at codegen time and shipped in the user's project.

| File | Job |
| --- | --- |
| [packages/core/lib/src/runtime/impl.dart](../packages/core/lib/src/runtime/impl.dart) | `ChannelRuntimeImpl`, `ControllerRuntimeImpl`, `SerializableRuntimeImpl` — instantiate channel, dispatch operation, document schema |
| [packages/core/lib/src/runtime/orm_impl.dart](../packages/core/lib/src/runtime/orm_impl.dart) | `ManagedEntityRuntimeImpl` — reflective property get/set, dynamic instance creation |
| [packages/runtime/lib/src/mirror_coerce.dart](../packages/runtime/lib/src/mirror_coerce.dart) | type coercion fallback |
| [packages/runtime/lib/src/mirror_context.dart](../packages/runtime/lib/src/mirror_context.dart) | `MirrorContext` — used at runtime to populate the registry on first access |

In production, these are deflected out by `conduit build` and replaced by
the generated runtime. In development, they run as-is. Removing
`conduit build` means we need a single registry built by `build_runner`
that works for both dev and prod.

### 3.3 Test-only

[packages/core/test/db/entity_mirrors_test.dart](../packages/core/test/db/entity_mirrors_test.dart),
[packages/runtime/test/coerce_test.dart](../packages/runtime/test/coerce_test.dart) —
they test mirror-based code paths. They go away with the underlying
production code, or get rewritten to drive the new generated runtimes.

## 4. Replacement strategy: `package:build` builders

`package:build_runner` is the standard Dart codegen tool. It powers
`json_serializable`, `freezed`, `mockito`, etc. Each builder reads
source files using `package:analyzer` (the same library
`packages/runtime` already depends on) and emits Dart files. Output is
incremental and cached. `dart compile exe` then runs against the
combined source.

We add a new package `conduit_build_runner` that exposes one builder
per existing `Compiler` plugin:

| Replaces | New builder | Reads | Emits |
| --- | --- | --- | --- |
| `ConduitCompiler` (channel half) | `ChannelBuilder` | classes extending `ApplicationChannel` | `<source>.channel.conduit.dart` |
| `ConduitCompiler` (controller half) | `ControllerBuilder` | classes extending `Controller` / `ResourceController` | `<source>.controller.conduit.dart` |
| `ConduitCompiler` (serializable half) | `SerializableBuilder` | classes implementing `Serializable` | `<source>.serializable.conduit.dart` |
| `DataModelCompiler` | `ManagedObjectBuilder` | classes extending `ManagedObject` | `<source>.managed.conduit.dart` |
| `Configuration` compiler in `conduit_config` | `ConfigurationBuilder` | classes extending `Configuration` | `<source>.config.conduit.dart` |

Plus a single aggregating builder that scans the build's outputs and
emits a top-level **registry** for the application:

```
$(rootDir)/.dart_tool/build/generated/<package>/lib/conduit.g.dart
```

The registry just instantiates each generated runtime and assigns the
result to `RuntimeContext.current.runtimes`. The user imports it at the
top of their `bin/server.dart`.

## 5. User-facing API

After this work, a Conduit project's `bin/server.dart` looks like this:

```dart
import 'package:conduit_core/conduit_core.dart';
import 'package:my_app/my_app.dart';
import 'package:my_app/conduit.g.dart' as conduit_runtime;

Future<void> main() async {
  conduit_runtime.bootstrap();              // populates RuntimeContext

  final app = Application<MyChannel>()
    ..options.configurationFilePath = 'config.yaml'
    ..options.port = 8888;
  await app.start(numberOfInstances: 2);
}
```

Build / run / ship:

```sh
dart pub get
dart run build_runner build               # emits *.conduit.dart files
dart bin/server.dart                       # dev (no AOT)
dart compile exe bin/server.dart -o build/server   # production
./build/server
```

`conduit build` becomes a thin wrapper for compatibility (one PR away
from being deleted) that does `dart run build_runner build && dart
compile exe …`. `conduit serve` already works on the running app — it
just needs `bootstrap()` to have been called.

`conduit create` templates change to include a `build.yaml` that
activates `conduit_build_runner` and a `bin/server.dart` shaped like
the above.

## 6. The discovery question

Mirrors today let the framework find every `ApplicationChannel` /
`Controller` / `ManagedObject` subclass without the user telling it where
they are. `package:build` doesn't have global discovery — each builder
runs over one source file at a time. That's a feature, not a bug; we
have to choose how to register subclasses.

**Decision: per-package registry, aggregated at the application root.**

- Each builder, when it processes a class, also writes a JSON manifest
  fragment as a build asset (e.g. `<source>.controller.conduit.json`).
- A second-stage builder, scoped to the app's root package, reads all
  manifest fragments visible to the app via `BuildStep.findAssets`, and
  emits `lib/conduit.g.dart` with a single `bootstrap()` function that
  imports every generated runtime and registers it.

This is exactly how `mocktail` / `mockito` / `auto_route` solve the same
problem. It avoids global mirror discovery and gives users per-file
incremental builds.

## 7. Migration plan (chunked)

Each phase is intended to land as its own PR. Each one is independently
shippable — the framework keeps working through the whole transition.

### Phase 0 — Scaffolding

- New package `packages/build_runner` (published as `conduit_build_runner`).
- `pubspec.yaml`, `build.yaml`, an empty `Builder` factory.
- No behavior change. Wired into the workspace; CI runs its tests.

### Phase 1 — `Serializable` builder

- Smallest contained surface. Builder reads classes implementing
  `Serializable`, emits a generated runtime equivalent to
  `SerializableRuntimeImpl`
  ([packages/core/lib/src/runtime/impl.dart:207-279](../packages/core/lib/src/runtime/impl.dart)).
- App-root aggregator scaffolded.
- Unit tests against a fixture project under
  `packages/build_runner/test/fixtures/`.
- Mirror-based `SerializableRuntimeImpl` stays in place; the builder is
  parallel and opt-in via `build.yaml`.

### Phase 2 — `ManagedObject` / ORM builder

- Bigger payload. Move the logic in `EntityBuilder` /
  `PropertyBuilder` / `ValidatorBuilder` from the analyzer-via-mirrors
  path they take today
  ([packages/core/lib/src/runtime/orm/entity_builder.dart](../packages/core/lib/src/runtime/orm/entity_builder.dart))
  to a `package:build` `Builder` that uses analyzer's `Element` API.
- Generate `ManagedEntityRuntimeImpl` per table definition class.
- The framework `ManagedDataModel.fromCurrentMirrorSystem()` doesn't
  actually use mirrors directly
  ([packages/core/lib/src/db/managed/data_model.dart:58-70](../packages/core/lib/src/db/managed/data_model.dart))
  — it iterates `RuntimeContext.current.runtimes`. So once the
  generated registry is populated, this constructor works with no
  changes; rename it to `.fromGeneratedRuntimes()` for clarity and keep
  the old name as a deprecated alias.

### Phase 3 — `Controller` / `ResourceController` builder

- Replaces `ControllerRuntimeImpl` and `ResourceControllerRuntimeImpl`.
- Operation discovery (`@Operation.get()` etc.) and parameter binding
  (`@Bind.path()` etc.) become AST-driven, with the dispatcher generated
  per controller class.
- Removes the path-variable-count-of-4 limitation (REFACTOR_CONTEXT §6
  #12) by generating dispatch code per arity.

### Phase 4 — `ApplicationChannel` builder + aggregator

- Channel runtime is the simplest of the four (it's mostly `name`,
  `instantiateChannel`, `runGlobalInitialization`).
- Once channel is generated, the app's `bootstrap()` function can take
  over from `MirrorContext._()` and we have a fully mirror-free runtime.

### Phase 5 — `Configuration` builder

- Mirror-based field reflection in `conduit_config` becomes a
  per-`Configuration` subclass builder.
- `conduit_config` no longer depends on `dart:mirrors`.

### Phase 6 — `conduit serve` / `conduit build` rewrite

- `conduit serve` invokes `dart run build_runner build` then runs the
  app on the current isolate.
- `conduit build` becomes a wrapper for `dart run build_runner build &&
  dart compile exe`. Pubspec rewriting code in
  [packages/core/lib/src/runtime/compiler.dart:54-152](../packages/core/lib/src/runtime/compiler.dart)
  is deleted.
- Templates updated.

### Phase 7 — Mirror cleanup

- Delete `dart:mirrors` imports from `packages/core` and
  `packages/runtime` and `packages/config`.
- Delete `packages/runtime/lib/src/mirror_coerce.dart`,
  `mirror_context.dart`, `build.dart`, `build_manager.dart`,
  `build_context.dart`, `generator.dart`, `compiler.dart`.
- Delete `packages/core/lib/src/runtime/compiler.dart`,
  `impl.dart`, `orm_impl.dart`, `resource_controller_*`, `orm/*`.
- Delete `packages/core/lib/src/utilities/mirror_helpers.dart`.
- `RuntimeContext` keeps its current shape but loses the `MirrorContext`
  factory; the only context left is the generated one populated by
  `bootstrap()`.
- The 1MB+ `BuildManager`/`Build`/`Generator` plumbing goes away
  alongside.

## 8. Open questions

These need resolution before phase 1 lands. Tracked here so we don't
re-litigate per-PR.

1. **`Application<T>` API.** Today users write
   `Application<MyChannel>()`. The runtime resolves `T` via
   `RuntimeContext.current[T]`. With a generated registry this still
   works, but only if the user has called `bootstrap()` first. Is that
   acceptable, or do we want `Application(MyChannelRuntime.instance)`
   passed explicitly? The former preserves existing user code; the
   latter makes the runtime dependency obvious. Lean: preserve.

2. **`build_runner` as a transitive dependency.** Putting it in
   `conduit_core`'s `dev_dependencies` is fine for development, but the
   user's app is what runs the builder. Either the user's `pubspec.yaml`
   has to add `build_runner` as a dev dep (the standard pattern, c.f.
   `json_serializable`), or `conduit_build_runner` declares a transitive
   dep that pulls it in. Lean: standard pattern, the `conduit create`
   templates include both.

3. **Backwards-compat for unmigrated apps.** During phases 1–4, the
   mirror-based runtimes still exist. We should make sure that if a
   user *only* runs build_runner, they get the generated runtime, but
   if they don't, they fall back to mirrors. The simplest model:
   `bootstrap()` short-circuits the mirror context. If `bootstrap()`
   was never called, the framework constructs a `MirrorContext` lazily
   as it does today. Removing this fallback is phase 7.

4. **Configuration of which classes get a runtime.** Today every
   `ApplicationChannel` / `Controller` / `ManagedObject` / `Serializable`
   in the workspace gets one. With per-source builders, users may have
   classes they don't want runtime-registered (e.g. internal abstract
   bases). Standard `package:build` answer: a `glob` in `build.yaml`,
   plus respect `@PreventCompilation`
   ([packages/runtime/lib/src/context.dart:71-73](../packages/runtime/lib/src/context.dart)).

5. **Web/Flutter compatibility.** Flutter doesn't have mirrors at all,
   and its build pipeline already uses `build_runner`. If a future
   Flutter integration emerges, this design is the only one that works.
   Worth verifying that none of our builders depend on `dart:io`-only
   APIs.

6. **Performance.** `package:build` cold builds on a large project can
   take 10–30s. Incremental builds are sub-second. The current
   `conduit build` is also slow. Worth measuring before/after on a
   reference project.

7. **Macros.** Dart macros are still experimental in 3.12 and not
   sufficient as-is for our needs (no `class` macros yet, declarations
   only). Skip for this iteration; revisit when macros stabilize and
   class augmentations land.

## 9. What "starting work" looks like in practice

The first PR after this design lands would be **phase 0**: an empty
`packages/build_runner` skeleton, wired into melos, with one trivial
builder that proves the codegen path works end-to-end (e.g. emits a
single `// generated by conduit_build_runner` line per Dart library). No
behavior change.

That gives us:
- A scaffolded place for the rest of the work to live.
- A `build.yaml` we can iterate on without churning user-facing code.
- A way to learn the package:build idioms before committing to the
  bigger surface.

After that, phases 1–4 land in sequence. Phase 5 (`Configuration`) is
independent and can land at any time after phase 0. Phase 6–7 are
end-state cleanup once the new path is the only path.

---

*Author note: this doc is a proposal. The mirror-call-site inventory in
§3 is grounded in `grep` output as of 2026-04-24; verify before acting
on individual file references. Every "delete X" in §7 needs a real
deprecation cycle if the package is published to pub — schedule
accordingly.*
