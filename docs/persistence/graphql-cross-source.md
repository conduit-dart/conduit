# GraphQL across SQL and graph stores

This document is the prose companion to `examples/graphql_cross_source/`. It walks the worked example end to end: a relational `User` table, a graph `Friendship` edge, and a single GraphQL query — `{ user(id: 1) { name friends { name } } }` — that reaches into both stores under one schema.

The G5 phase of the Conduit GraphQL plan adds three primitives to make this pattern viable:

1. **`SchemaBuilder.fromPersistence`** — emits one `GraphQLSchema` over both halves of a `Persistence<G>` umbrella. Every emitted ObjectType is source-tagged so callers can introspect which half emitted what.
2. **`PersistenceResolverFactory`** — bundles `SqlResolverFactory` and `GraphResolverFactory` and threads them through the unified emission path. Optional — apps that do all stitching by hand can skip this.
3. **`@FieldAuthorize`** — a field-level authorization annotation honored by the resolver-wrapping machinery. Failed scope checks raise GraphQL execution errors at the field path.

> **What `fromPersistence` does NOT do.** It does not auto-join SQL rows to graph nodes. Cross-source filters require a hand-written stitching resolver — exactly what this document demonstrates. The umbrella's job is to *route* per-field, never to *fan out* per-query.

## The shape

The example lives under `examples/graphql_cross_source/`. The relevant files are:

- `lib/graphql_cross_source_example.dart` — the channel, the schema build, and the stitching resolver.
- `bin/main.dart` — the binary that boots an `Application<CrossSourceChannel>` on port 8888.
- `test/example_test.dart` — smoke tests verifying both halves wire and the stitching resolver returns friends.

In production the example replaces the toy stores (`_FakeSqlStore` / `_FakeGraphStore`) with `PostgreSQLPersistentStore` and `Neo4jPersistentStore`. The wiring is otherwise identical.

## Step 1 — declare the domain on each side

The relational side declares a regular `ManagedObject`:

```dart
class User extends ManagedObject<_User> implements _User {}

class _User {
  @primaryKey
  int? id;

  @Column(unique: true)
  String? email;

  @Column(nullable: true)
  String? displayName;
}
```

The graph side declares a `Profile` node and a `Friendship` edge between profiles. The graph node carries a `userId` property pointing back to the SQL row — that's the join key:

```dart
class Profile extends GraphNode<Profile> {
  Profile() : super(labels: const [GraphLabel.unchecked('Profile')]);

  int? get userId => this['userId'] as int?;
  set userId(int? v) => this['userId'] = v;
}

class Friendship extends GraphEdge<Profile, Profile> {
  Friendship({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Friendship'));

  DateTime? get since => this['since'] as DateTime?;
  set since(DateTime? v) => this['since'] = v;
}
```

The two halves intentionally share no Dart class names. (When they would — see `QueryRootCollisionPolicy` below for renaming options.)

## Step 2 — wire the umbrella in `prepare()`

`Persistence<G>` carries one optional SQL store and one optional graph store. Construct it once and stash both contexts on it:

```dart
typedPersistence = Persistence<GraphPersistentStore>(
  sql: PostgreSQLPersistentStore.fromConnectionInfo(...),
  graph: Neo4jPersistentStore(Uri.parse('bolt://localhost:7687')),
);

final sqlModel = ManagedDataModel([User]);
typedPersistence.sqlContext = ManagedContext(sqlModel, typedPersistence.sql);

final graphModel = GraphDataModel()
  ..registerNode<Profile>(label: const GraphLabel.unchecked('Profile'))
  ..registerEdge<Friendship, Profile, Profile>(
    label: const GraphLabel.unchecked('Friendship'),
  );
typedPersistence.graphContext = GraphContext(graphModel, typedPersistence.graph);
```

`Persistence<G>` is graph-store-agnostic; `G` is the application's chosen graph type (`GraphPersistentStore` here for backend portability, `Neo4jPersistentStore` for tighter typing).

## Step 3 — derive the unified schema

`SchemaBuilder.fromPersistence` walks both halves and returns a `PersistenceSchema`:

```dart
final persistenceSchema = SchemaBuilder().fromPersistence(typedPersistence);
```

The result carries:

- `schema` — the unified `GraphQLSchema` ready for `GraphQLController`.
- `sqlObjectTypes` — `Map<String, GraphQLObjectType>` keyed by entity name.
- `graphObjectTypes` — same shape, keyed by graph label.
- `sourceFor(type)` — returns `'sql'` or `'graph'` for an emitted ObjectType.

The Query root holds fields from both halves:

```graphql
type Query {
  # SQL side
  users: [User!]!
  user(id: String!): User
  # Graph side
  profiles: [Profile!]!
  profile(id: String!): Profile
  friendships: [Friendship!]!
}
```

### Collision policy

When SQL and graph entities want the same query-root field name, you have three options:

- `QueryRootCollisionPolicy.error` (default) — `StateError` at build time.
- `QueryRootCollisionPolicy.prefixGraph` — graph fields get a `g_` prefix on collision.
- `QueryRootCollisionPolicy.prefixRelational` — SQL fields get an `r_` prefix on collision.

The error-default is conservative: in a healthy schema, name collisions are usually a sign that your domain split is wrong, not that you need a renamer. Pick a softer policy when you're aware of the collision and have decided which side is canonical.

## Step 4 — stitching the cross-source query

The cross-source query the user wants:

```graphql
query Q($id: ID!) {
  user(id: $id) {
    id
    email
    displayName
    friends {
      id
      email
      displayName
    }
  }
}
```

There is no `User.friends` field in the auto-derived schema — the SQL walker doesn't know about graph edges, and the graph walker doesn't know about SQL rows. We attach a hand-rolled stitching resolver to the SQL `User` object type:

```dart
void _attachStitchingResolver() {
  final userType = persistenceSchema.sqlObjectTypes['User']!;
  final friendsField = GraphQLObjectField<dynamic, dynamic>(
    'friends',
    GraphQLListType(userType.nonNullable()).nonNullable(),
    resolve: (parent, args) async {
      // Step 1 — who are we?
      final userId = parent is ManagedObject
          ? parent['id'] as int?
          : parent is Map
              ? parent['id'] as int?
              : null;
      if (userId == null) return const <Object>[];

      // Step 2 — walk graph friendships from this user's profile.
      // In production: graphContext.match<Profile>(...).fetch()
      // followed by traverse(profile, Friendship). The fake store
      // here jumps straight to the answer.
      final friendUserIds = (typedPersistence.graph as _FakeGraphStore)
          .friendsOf(userId);

      // Step 3 — re-fetch the friend rows from SQL.
      // In production: Query<User>(...).where(u => u.id.oneOf(...)).fetch()
      // batched via the per-request DataLoader so a 1000-friend
      // payload still hits SQL once.
      final sqlStore = typedPersistence.sql as _FakeSqlStore;
      return [
        for (final id in friendUserIds)
          if (sqlStore.rows[id] != null) sqlStore.rows[id]!,
      ];
    },
  );
  userType.fields.add(friendsField);
}
```

Three steps, three round-trips:

1. **SQL → user identity.** The parent of the `friends` field is the `User` row already fetched by the upstream `user(id:)` resolver. Read its primary key.
2. **Graph → friendship walk.** Run a graph traversal from the user's `Profile` node along `Friendship` edges. In production, this is `graphContext.traverse<Profile>(profile, Friendship)`.
3. **SQL → friend hydration.** The traversal returns graph profiles whose `userId` properties point back at SQL rows. Re-fetch those rows in one batched `WHERE id IN (...)` query (use a `DataLoader` per request so multiple `friends` resolutions share the round-trip).

> **DataLoader matters here.** Without it, `users { friends { friends { friends } } }` becomes `O(N^3)` SQL round-trips. The G3 `DataLoader` lives on the per-request registry and is the same primitive any other relational batching uses; the stitching resolver opts in by calling `registry.getOrAdd(...).load(id)` instead of fetching directly.

## Step 5 — field-level authorization

`@FieldAuthorize` (the annotation) marks a property as scope-gated. `FieldAuthPolicy` (the runtime lookup) maps property descriptors to their declarations.

On the SQL side, attach the annotation to your `ManagedObject`:

```dart
class _User {
  @primaryKey
  int? id;

  @Column(unique: true)
  String? email;

  /// Only callers holding `pii:read` may see the SSN.
  @FieldAuthorize(scopes: ['pii:read'])
  @Column(nullable: true)
  String? ssn;
}
```

The annotation on the source is documentation for human reviewers; Conduit's runtime data model does not preserve arbitrary property annotations through the build (only `Validate`, `ResponseModel`, and `ResponseKey` are first-class). You also build a `FieldAuthPolicy` at startup mapping the same fields to the same declarations:

```dart
final policy = MapFieldAuthPolicy({
  // Look up the descriptor on the registered ManagedDataModel:
  managedContext.dataModel!
      .entityForType(User)
      .attributes['ssn']!: const FieldAuthorize(scopes: ['pii:read']),
});

final factory = PersistenceResolverFactory<GraphPersistentStore>(
  sql: SqlResolverFactory(managedContext),
  graph: GraphResolverFactory(graphContext),
);

final hookSet = factory.hooks(authPolicy: policy);
```

Pass `hookSet` (or directly `factory` and `authPolicy`) into `fromPersistence`:

```dart
final persistenceSchema = SchemaBuilder().fromPersistence(
  typedPersistence,
  resolverFactory: factory,
  authPolicy: policy,
);
```

When a request without `pii:read` reaches `User.ssn`, the resolver wrapper raises a `GraphQLException` and the executor surfaces it as an entry in `errors[]` keyed at the field path; the rest of the response continues to populate (per the GraphQL execution spec).

`@FieldAuthorize` also accepts an `allowOwner: (parent, request) -> bool` callback that short-circuits the scope check when the requester is the resource owner. The check runs only on scope-mismatch, so it never adds latency for fully-scoped callers.

### Graph-side asymmetry

`GraphNode` does not currently support per-property annotations — graph property declarations live in `GraphSchemaConfig`, not on the class. G5 keeps the surface uniform by extending `GraphPropertyDescriptor` with an optional `auth:` field:

```dart
GraphSchemaConfig(
  nodes: {
    Profile: const GraphNodeSchemaConfig(
      properties: [
        GraphPropertyDescriptor(name: 'displayName', type: GraphPropertyType.string),
        GraphPropertyDescriptor(
          name: 'phoneNumber',
          type: GraphPropertyType.string,
          isNullable: true,
          auth: FieldAuthorize(scopes: ['pii:read']),
        ),
      ],
    ),
  },
);
```

The graph-side resolver wrapper consults the descriptor's `auth` first, then falls back to a `GraphPropertyAuthKey(Profile, 'phoneNumber')` lookup against the policy — either path is valid.

## Limits, gotchas, and what's next

- **No automatic joins.** The umbrella never invents a join. If you find yourself wishing it did, that's a design signal: the join belongs in the application layer (a stitching resolver), not in the framework.
- **No cross-store transactions.** See `docs/persistence/multi-backend.md` — the umbrella explicitly does not coordinate XA/2PC. The stitching resolver runs reads in sequence; writes that span stores need an outbox or eventual-consistency strategy.
- **Source tagging is read-only metadata.** The `sourceFor(type)` map is for callers that want to reason about the schema at build time (e.g., a custom auth gate that's stricter on graph types). The map does not affect resolution.
- **The `@FieldAuthorize` annotation is documentation only without a `FieldAuthPolicy`.** Reflection-based annotation scraping is not in G5 because `dart:mirrors` is being deprecated. A future phase can add a `build_runner` transformer that emits the policy from the source — until then, declare the policy explicitly.

## Subscriptions

GraphQL subscriptions are **out of scope for the entire G1–G5 plan**. Conduit has no WebSocket transport in core, and the existing GraphQL infrastructure here targets the GraphQL-over-HTTP spec (POST + GET only). Adding subscriptions would require a separate WebSocket transport, a message-bus integration, and a re-think of the per-request `DataLoader` lifecycle. v0.6+ territory.

---

For the executable end of this document, see `examples/graphql_cross_source/`. For the schema-derivation reference (G2 + G3 + G4 phase docs), see `packages/graphql/README.md`.
