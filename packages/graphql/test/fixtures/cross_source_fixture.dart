/// Cross-source fixture for the G5 [SchemaBuilder.fromPersistence] tests.
///
/// Mirrors the worked example in `docs/persistence/graphql-cross-source.md`:
/// a relational `User` ManagedObject + a graph `Friendship` edge between
/// graph `Profile` nodes. The two sides intentionally share NO Dart
/// type names so the cross-source unified schema can be inspected
/// without ambiguity.
///
/// The relational `User` lowers to a SQL-side ObjectType; the graph
/// `Profile` and `Friendship` lower to graph-side ObjectTypes. The
/// query root shows fields from both, and the source tag side-channel
/// distinguishes them.
library;

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graphql/conduit_graphql.dart';

// -- SQL side ---------------------------------------------------------------

class User extends ManagedObject<_User> implements _User {}

class _User {
  @primaryKey
  int? id;

  @Column(unique: true)
  String? email;

  @Column(nullable: true)
  String? displayName;
}

// -- Graph side --------------------------------------------------------------

class Profile extends GraphNode<Profile> {
  Profile() : super(labels: const [GraphLabel.unchecked('Profile')]);
}

class Friendship extends GraphEdge<Profile, Profile> {
  Friendship({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Friendship'));

  DateTime? get since => this['since'] as DateTime?;
  set since(DateTime? v) => this['since'] = v;
}

// -- Collision fixture (used to exercise QueryRootCollisionPolicy) ------------

/// SQL-side ManagedObject named `Account`, exposed at query field `account`/
/// `accounts`. The graph-side `Account` node intentionally shares the
/// type name on the graph label below — this collision is the trigger
/// for [QueryRootCollisionPolicy].
class Account extends ManagedObject<_Account> implements _Account {}

class _Account {
  @primaryKey
  int? id;

  @Column(nullable: true)
  String? handle;
}

class GraphAccount extends GraphNode<GraphAccount> {
  GraphAccount() : super(labels: const [GraphLabel.unchecked('Account')]);
}

// -- Helpers ----------------------------------------------------------------

ManagedDataModel buildCrossSourceSqlModel() => ManagedDataModel([User]);

ManagedDataModel buildCollisionSqlModel() => ManagedDataModel([Account]);

GraphDataModel buildCrossSourceGraphModel() {
  final model = GraphDataModel();
  model.registerNode<Profile>();
  model.registerEdge<Friendship, Profile, Profile>();
  return model;
}

GraphDataModel buildCollisionGraphModel() {
  final model = GraphDataModel();
  model.registerNode<GraphAccount>(
    label: const GraphLabel.unchecked('Account'),
  );
  return model;
}

GraphSchemaConfig buildCrossSourceGraphConfig() => GraphSchemaConfig(
      nodes: {
        Profile: const GraphNodeSchemaConfig(
          properties: [
            GraphPropertyDescriptor(
              name: 'displayName',
              type: GraphPropertyType.string,
            ),
          ],
        ),
      },
      edges: {
        Friendship: const GraphEdgeSchemaConfig(
          properties: [
            GraphPropertyDescriptor(
              name: 'since',
              type: GraphPropertyType.datetime,
              isNullable: true,
            ),
          ],
        ),
      },
    );

GraphSchemaConfig buildCollisionGraphConfig() => GraphSchemaConfig(
      nodes: {
        GraphAccount: const GraphNodeSchemaConfig(
          properties: [
            GraphPropertyDescriptor(
              name: 'handle',
              type: GraphPropertyType.string,
            ),
          ],
        ),
      },
    );
