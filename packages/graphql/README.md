# conduit_graphql

GraphQL HTTP transport for [Conduit](https://www.theconduit.dev). Mounts a
`GraphQLController` over a hand-written `GraphQLSchema`, implementing the
[GraphQL-over-HTTP spec](https://graphql.github.io/graphql-over-http/draft/)
for `POST` (queries + mutations) and `GET` (queries only).

## Status — G1 of the GraphQL evaluation plan

This is the **first phase** of a five-phase delivery. G1 ships the HTTP
transport only; everything that talks to a Conduit data model is deferred
to a later phase.

| Phase  | Scope | Ships in this package? |
|--------|-------|------------------------|
| **G1** | Controller, parse + validate + execute, JSON envelope, GET-of-mutation rejection, introspection | **Yes** |
| G2     | Derive a `GraphQLSchema` from `ManagedDataModel` | Stub only (`SchemaBuilder` throws `UnimplementedError`) |
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

## What this package does NOT do (yet)

* **No schema derivation** — `SchemaBuilder` is a `UnimplementedError`
  stub. Caller hand-assembles the `GraphQLSchema`. (G2.)
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
