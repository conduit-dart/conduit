/// Test-only graph fixture used by the G4 schema-derivation tests.
///
/// Two node types (`User`, `Post`) plus three edge types (`Friend`,
/// `Authored`, `Liked`), deliberately chosen to exercise:
///
/// * single-label and multi-label nodes (`User` is also labeled
///   `Account`);
/// * three distinct edge kinds, including one with edge properties
///   (`Friend.since`, `Liked.score`);
/// * homogeneous (`User -> User`) and heterogeneous (`User -> Post`)
///   endpoints;
/// * the `exposeGraphEdgesAsConnections` flag's destination-list-
///   alongside-edge-list handling;
/// * the schemaless-properties opt-in (only `Post` opts in here, so
///   the `properties: JSON!` field surfaces on `Post` but not `User`).

library;

import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graphql/conduit_graphql.dart';

// -- Node types -------------------------------------------------------------

class User extends GraphNode<User> {
  /// Multi-label: `User` carries both `User` and `Account` in the
  /// store. The schema builder surfaces this as a `UserOrAccount`
  /// union of two object types.
  User()
      : super(
          labels: const [
            GraphLabel.unchecked('User'),
            GraphLabel.unchecked('Account'),
          ],
        );
}

class Post extends GraphNode<Post> {
  Post() : super(labels: const [GraphLabel.unchecked('Post')]);
}

// -- Edge types --------------------------------------------------------------

class Friend extends GraphEdge<User, User> {
  Friend({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Friend'));

  DateTime? get since => this['since'] as DateTime?;
  set since(DateTime? v) => this['since'] = v;
}

class Authored extends GraphEdge<User, Post> {
  Authored({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Authored'));
}

class Liked extends GraphEdge<User, Post> {
  Liked({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Liked'));

  int? get score => this['score'] as int?;
  set score(int? v) => this['score'] = v;
}

// -- Fixtures ---------------------------------------------------------------

/// Builds a populated [GraphDataModel] with the three edge types and
/// two node types declared above.
GraphDataModel buildSocialGraphDataModel() {
  final model = GraphDataModel();
  model.registerNode<User>();
  model.registerNode<Post>();
  model.registerEdge<Friend, User, User>();
  model.registerEdge<Authored, User, Post>();
  model.registerEdge<Liked, User, Post>();
  return model;
}

/// Builds the matching [GraphSchemaConfig] declaring property shapes,
/// the `User -> Account` union, and the schemaless opt-in for `Post`.
///
/// [exposeEdges] toggles the `exposeGraphEdgesAsConnections` flag so a
/// single fixture covers both shapes.
GraphSchemaConfig buildSocialGraphSchemaConfig({bool exposeEdges = false}) {
  return GraphSchemaConfig(
    exposeGraphEdgesAsConnections: exposeEdges,
    nodes: {
      User: const GraphNodeSchemaConfig(
        unionLabels: ['Account'],
        properties: [
          GraphPropertyDescriptor(
            name: 'name',
            type: GraphPropertyType.string,
          ),
          GraphPropertyDescriptor(
            name: 'age',
            type: GraphPropertyType.integer,
            isNullable: true,
          ),
        ],
      ),
      Post: const GraphNodeSchemaConfig(
        hasSchemalessProperties: true,
        properties: [
          GraphPropertyDescriptor(
            name: 'title',
            type: GraphPropertyType.string,
          ),
        ],
      ),
    },
    edges: {
      Friend: const GraphEdgeSchemaConfig(
        properties: [
          GraphPropertyDescriptor(
            name: 'since',
            type: GraphPropertyType.datetime,
            isNullable: true,
          ),
        ],
      ),
      Authored: const GraphEdgeSchemaConfig(),
      Liked: const GraphEdgeSchemaConfig(
        properties: [
          GraphPropertyDescriptor(
            name: 'score',
            type: GraphPropertyType.integer,
            isNullable: true,
          ),
        ],
      ),
    },
  );
}
