# conduit_graphql

GraphQL HTTP transport for [Conduit](https://www.theconduit.dev). Mounts a
`GraphQLController` over a `GraphQLSchema` — either hand-written or
derived from your `ManagedDataModel` — and implements the
[GraphQL-over-HTTP spec](https://graphql.github.io/graphql-over-http/draft/)
for `POST` (queries + mutations) and `GET` (queries only).

## Status — G2 of the GraphQL evaluation plan

This is the **second phase** of a five-phase delivery. G1 shipped the
HTTP transport; G2 adds schema derivation. Resolver wiring is still
deferred.

| Phase  | Scope | Ships in this package? |
|--------|-------|------------------------|
| G1     | Controller, parse + validate + execute, JSON envelope, GET-of-mutation rejection, introspection | Yes |
| **G2** | Derive a `GraphQLSchema` from `ManagedDataModel` (read-only, no resolvers) | **Yes** |
| G3     | SQL resolvers + dataloader against `Query<T>`     | No |
| G4     | Graph resolvers against `GraphQuery<N>` (Neo4j)   | No |
| G5     | Cross-source dispatch + `@FieldAuthorize`         | No |

GraphQL **subscriptions are out of scope for the entire plan**; Conduit
has no WebSocket transport in core.

## Install

Add to your `pubspec.yaml`:

```yaml
dependencies:
  conduit_core: ^6.0.0
  conduit_graphql: ^6.0.0
```

`conduit_graphql` re-exports the surfaces of `graphql_schema2`,
`graphql_parser2`, and `graphql_server2` — you do not need to add those
packages to your own `pubspec.yaml` to assemble a hand-written schema.

## Wire-up example

```dart
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_graphql/conduit_graphql.dart';

final helloSchema = graphQLSchema(
  queryType: objectType('Query', fields: [
    field('hello', graphQLString, resolve: (_, _) => 'world'),
    field(
      'greet',
      graphQLString.nonNullable(),
      inputs: [GraphQLFieldInput('name', graphQLString.nonNullable())],
      resolve: (_, args) => 'Hello, ${args['name']}!',
    ),
  ]),
);

class MyChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    router.route('/graphql').link(() => GraphQLController(helloSchema));
    return router;
  }
}
```

Then:

```bash
$ curl -sX POST http://localhost:8888/graphql \
    -H 'content-type: application/json' \
    -d '{"query":"{ hello, greet(name: \"alice\") }"}'
{"data":{"hello":"world","greet":"Hello, alice!"}}
```

## Wire format

### Request — `POST /graphql` with `application/json`

```json
{
  "query":         "<GraphQL document>",
  "operationName": "<optional>",
  "variables":     { "<name>": <value>, ... },
  "extensions":    { ... }
}
```

`extensions` is accepted but ignored in G1.

### Request — `POST /graphql` with `application/graphql`

The body is the raw query document. No JSON envelope.

### Request — `GET /graphql`

```
GET /graphql?query=<doc>&operationName=<name>&variables=<JSON-encoded>
```

Per the spec, `GET` is restricted to `query` operations. Sending a
`mutation` over `GET` returns `405 Method Not Allowed`.

### Response

Always JSON. Two media types are supported:

* `application/json` — the legacy default; what you get unless you opt in.
* `application/graphql-response+json` — the modern spec-aligned media
  type. Send `Accept: application/graphql-response+json` to receive it.
  This package registers the codec with Conduit's `CodecRegistry` on
  first `GraphQLController` construction; you do not need to register
  it yourself.

```json
{
  "data":   ...,
  "errors": [
    {
      "message":    "...",
      "locations":  [{ "line": 1, "column": 9 }],
      "path":       [...],
      "extensions": { ... }
    }
  ]
}
```

### HTTP status codes

* `200` — request was processed. Field-resolver runtime errors land
  here, with `data: null` and a populated `errors[]` (per spec §7.1.2).
* `400` — malformed body, parse error, validation error, missing
  `query`, malformed `?variables=`, or variable-coercion failure.
* `405` — `GET` of a `mutation` or `subscription`.

Field-existence validation is performed locally before execution to
work around an upstream gap in `graphql_server2` v6.5.0 — see "Known
limitations" below.

## Schema derivation (G2)

`SchemaBuilder.fromManagedDataModel(model)` walks every `ManagedEntity`
in your data model and emits a read-only GraphQL schema:

```dart
import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';

final dataModel = ManagedDataModel([User, Post, Comment]);
final schema = SchemaBuilder().fromManagedDataModel(dataModel);

// Mount as you would any hand-written schema.
router.route('/graphql').link(() => GraphQLController(schema));
```

Note the `hide SchemaBuilder` on `conduit_core`'s import: Conduit has
two unrelated `SchemaBuilder` classes — the migration helper from
`conduit_core` and the GraphQL builder from this package. Hide whichever
one you don't need at the call site.

### What the walker emits

* One `GraphQLObjectType` per `ManagedEntity`.
* Scalar columns lower per the table below.
* Relationships surface in both directions: `User.posts: [Post!]!` and
  `Post.author: User!` are both present.
* A `Query` root with two fields per entity:
  * `<plural>: [<Entity>!]!` (list-all),
  * `<singular>(<pk>: <pkType>!): <Entity>` (find-by-pk).
* All field resolvers are `null` — execution lands in G3. Schema
  introspection, validation, and SDL printing all work today.

### Scalar mapping

| Conduit `ManagedPropertyType` | GraphQL                         |
|-------------------------------|---------------------------------|
| `integer`                     | `Int`                           |
| `bigInteger`                  | `String` (default; `Int` if `bigIntegerAsString: false`) |
| `string`                      | `String`                        |
| `datetime`                    | `DateTime` (custom scalar)      |
| `boolean`                     | `Boolean`                       |
| `doublePrecision`             | `Float`                         |
| `document`                    | `String` (JSON-encoded)         |
| `list`                        | `[T!]` (T mapped per this row)  |
| `map`                         | `String` (JSON-encoded)         |
| enum-typed `string`           | `String` (raw enum name)        |

### Nullability rules

| Source                                              | GraphQL nullability     |
|-----------------------------------------------------|-------------------------|
| Primary key                                         | non-null                |
| Attribute, `isNullable: false`, no `defaultValue`   | non-null                |
| Attribute, `isNullable: true` or has `defaultValue` | nullable                |
| Output-side `@Serialize` transient                  | nullable                |
| Input-only `@Serialize` transient                   | excluded from schema    |
| `belongsTo` with `Relate(isRequired: true)`         | non-null                |
| `belongsTo` without `isRequired`                    | nullable                |
| `hasOne`                                            | nullable                |
| `hasMany`                                           | `[Type!]!` (always)     |

### G2 schema-derivation limitations

* **Naive pluralization.** Singular is `entity.name` lowercased
  (`User -> user`); plural appends `s`/`es`/`ies` per simple rules.
  Words like `Mouse -> mouses`, `Octopus -> octopuses` will be wrong.
  A future `@SchemaName('users')`-style annotation will allow per-
  entity overrides; for now, work around the case by hand-authoring
  the affected types or contributing the override hook.
* **`Document` columns serialize as JSON strings**, not nested object
  types. Apps that need typed access to subdocuments must define a
  parallel projection by hand.
* **No filter / sort / pagination arguments.** List-all fields take
  zero arguments today. G3 adds a `where:` / `orderBy:` / `limit:` /
  `offset:` argument set lowering to `Query<T>` predicates.
* **No mutations.** The derived schema is read-only — there are no
  generated input object types, and the controller will reject GET
  but not POST mutations against the derived schema (because there is
  no `mutationType` to match against).
* **Many-to-many join tables surface as their own `ObjectType` plus
  two lists** (`Post.tags: [PostTag!]!`, `Tag.posts: [PostTag!]!`).
  We do not auto-flatten the join. Build a hand-written field for the
  flattened view if you need one in v1.
* **Enum columns surface as `String`**, not `enum`. Surfacing them as
  GraphQL `enum` types is straightforward but requires either a
  registry walk or a stable name for the Dart enum at runtime; tracked
  for a future minor.
* **bigInteger scalars default to `String`** to dodge GraphQL `Int`'s
  signed-32-bit overflow risk. Pass `SchemaBuilder(bigIntegerAsString:
  false)` to opt back into `Int` if you know your big-int columns are
  32-bit safe.
* **Custom scalars are reachable via field-level introspection but
  not the global `__schema { types }` list.** This is a
  `graphql_server2` v6.5.0 limitation: its type-collection walker
  doesn't add bare scalars to the traversed set. Tools that introspect
  through field types (e.g. GraphiQL hovering over a `DateTime` field)
  will see the scalar correctly; a `__schema { types { name } }` query
  will not list it.
* **Single-entity types (`objectTypeFor`) build a one-off registry**
  with empty stubs for any related entities outside the call. Use
  `fromManagedDataModel` for full schemas where relationship
  destinations need their fields populated.

### Rendering SDL

The package ships a minimal `printSchema()` for use in golden tests
and documentation pipelines:

```dart
import 'package:conduit_graphql/conduit_graphql.dart';

final sdl = printSchema(schema);
print(sdl);
```

The printer covers the surface `SchemaBuilder` emits today (object
types, scalars, lists, non-null wrappers, field arguments, descriptions).
Anything outside that surface (interfaces, unions, enums, directives,
mutations, input objects) is not yet supported and will throw — by
design, so adding e.g. mutation support can't accidentally rely on a
stale printer.

## What this package does NOT do (yet)

* **No resolver framework** — there is no `Query<T>`/`GraphQuery<N>`
  integration. Resolvers are caller-provided closures. (G3 / G4.)
* **No dataloader** — N+1 mitigation is on the caller until G3.
* **No field-level authorization** — `@FieldAuthorize` is a G5 surface.
  Per-resolver auth checks against `request.authorization` are the
  current pattern; the conduit `Request` is exposed to resolvers via
  `globalVariables['conduitRequest']`.
* **No subscriptions** — out of scope for the entire plan; Conduit core
  has no WebSocket transport.

## Known limitations (G1)

* `graphql_server2` v6.5.0 silently drops field selections that don't
  exist on the parent type. We work around this with a minimal
  pre-execution validator that rejects unknown root-and-nested fields
  with HTTP 400 / `errors[]`. Fragment spreads and inline fragments are
  not yet checked by the local validator and fall through to the
  upstream executor.
* Field-resolver runtime errors are surfaced as a single error with the
  thrown object's `toString()` as `message`. Path information is not
  yet populated; `graphql_server2` does not attribute paths to its
  thrown `GraphQLException`s, and the path machinery lands in G3
  alongside the dataloader.

## License

BSD-3-Clause, matching the rest of the Conduit framework.
