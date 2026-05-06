import 'package:conduit_graph/conduit_graph.dart';
import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
import 'package:test/test.dart';

// Test fixtures: tiny social graph reused across tests.

class User extends GraphNode<User> {
  User({String? name, int? age}) : super(labels: [GraphLabel('User')]) {
    if (name != null) this['name'] = name;
    if (age != null) this['age'] = age;
  }
}

class Post extends GraphNode<Post> {
  Post() : super(labels: [GraphLabel('Post')]);
}

class Friend extends GraphEdge<User, User> {
  Friend({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Friend'));
}

class Authored extends GraphEdge<User, Post> {
  Authored({required super.from, required super.to})
      : super(label: const GraphLabel.unchecked('Authored'));
}

void main() {
  group('CypherEmitter — pattern lowering', () {
    test('single-node anchor', () {
      final pattern = GraphPattern<User>.build((_) {}, variable: 'u');
      final stmt = emitPattern(pattern);
      expect(stmt.cypher, 'MATCH (u:User) RETURN u');
      expect(stmt.parameters, isEmpty);
    });

    test('outgoing single hop with terminal label', () {
      final pattern = GraphPattern<User>.build(
        (u) => u.connectedTo<Friend>(toLabel: GraphLabel('User')),
        variable: 'u',
      );
      final stmt = emitPattern(pattern);
      expect(
        stmt.cypher,
        'MATCH (u:User)-[r0:Friend]->(m0:User) RETURN u',
      );
    });

    test('outgoing hop without terminal label leaves the far side bare', () {
      final pattern = GraphPattern<User>.build(
        (u) => u.connectedTo<Friend>(),
        variable: 'u',
      );
      final stmt = emitPattern(pattern);
      expect(stmt.cypher, 'MATCH (u:User)-[r0:Friend]->(m0) RETURN u');
    });

    test('incoming direction emits a left-pointing arrow', () {
      final pattern = GraphPattern<User>.build(
        (u) => u.connectedTo<Friend>(
          direction: GraphRelationshipDirection.incoming,
          toLabel: GraphLabel('User'),
        ),
      );
      expect(
        emitPattern(pattern).cypher,
        contains('<-[r0:Friend]-'),
      );
    });

    test('undirected direction emits no arrow heads', () {
      final pattern = GraphPattern<User>.build(
        (u) => u.connectedTo<Friend>(
          direction: GraphRelationshipDirection.undirected,
          toLabel: GraphLabel('User'),
        ),
      );
      expect(
        emitPattern(pattern).cypher,
        contains('-[r0:Friend]-(m0:User)'),
      );
    });

    test('multi-hop chain numbers each hop deterministically', () {
      final pattern = GraphPattern<User>.build(
        (u) => u
          ..connectedTo<Friend>(toLabel: GraphLabel('User'))
          ..connectedTo<Authored>(toLabel: GraphLabel('Post')),
      );
      final stmt = emitPattern(pattern);
      expect(
        stmt.cypher,
        startsWith(
          'MATCH (n:User)-[r0:Friend]->(m0:User)-[r1:Authored]->(m1:Post)',
        ),
      );
    });

    test('user-pinned terminal variable is honored', () {
      final pattern = GraphPattern<User>.build(
        (u) => u.connectedTo<Authored>(
          toLabel: GraphLabel('Post'),
          toVariable: 'p',
        ),
      );
      expect(
        emitPattern(pattern).cypher,
        contains('-[r0:Authored]->(p:Post)'),
      );
    });
  });

  group('CypherEmitter — filter rendering', () {
    String renderFilter(GraphFilterExpression f, {String anchor = 'n'}) =>
        CypherEmitter().emitFilter(f, anchor: anchor);

    test('equality maps to =', () {
      final f = GraphPropertyFilter(
        property: 'name',
        operator: GraphFilterOperator.equal,
        value: 'alice',
      );
      expect(renderFilter(f), 'n.name = \$p0');
    });

    test('inequality maps to <>', () {
      final f = GraphPropertyFilter(
        property: 'role',
        operator: GraphFilterOperator.notEqual,
        value: 'admin',
      );
      expect(renderFilter(f), 'n.role <> \$p0');
    });

    test('comparison operators render correctly', () {
      final cases = {
        GraphFilterOperator.greaterThan: '>',
        GraphFilterOperator.greaterThanOrEqual: '>=',
        GraphFilterOperator.lessThan: '<',
        GraphFilterOperator.lessThanOrEqual: '<=',
      };
      cases.forEach((op, sym) {
        final f = GraphPropertyFilter(
          property: 'age',
          operator: op,
          value: 21,
        );
        expect(renderFilter(f), 'n.age $sym \$p0',
            reason: 'operator $op should render as $sym');
      });
    });

    test('string ops map to CONTAINS / STARTS WITH / ENDS WITH', () {
      expect(
        renderFilter(GraphPropertyFilter(
          property: 'name',
          operator: GraphFilterOperator.contains,
          value: 'al',
        )),
        'n.name CONTAINS \$p0',
      );
      expect(
        renderFilter(GraphPropertyFilter(
          property: 'name',
          operator: GraphFilterOperator.startsWith,
          value: 'a',
        )),
        'n.name STARTS WITH \$p0',
      );
      expect(
        renderFilter(GraphPropertyFilter(
          property: 'name',
          operator: GraphFilterOperator.endsWith,
          value: 'e',
        )),
        'n.name ENDS WITH \$p0',
      );
    });

    test('IN renders with the bound list value', () {
      final emitter = CypherEmitter();
      final cypher = emitter.emitFilter(GraphPropertyFilter(
        property: 'role',
        operator: GraphFilterOperator.inList,
        value: ['admin', 'staff'],
      ));
      expect(cypher, 'n.role IN \$p0');
      expect(emitter.parameters['p0'], ['admin', 'staff']);
    });

    test('isNull / isNotNull do not bind a parameter', () {
      final e1 = CypherEmitter();
      final s1 = e1.emitFilter(GraphPropertyFilter(
        property: 'deleted_at',
        operator: GraphFilterOperator.isNull,
      ));
      expect(s1, 'n.deleted_at IS NULL');
      expect(e1.parameters, isEmpty);

      final e2 = CypherEmitter();
      final s2 = e2.emitFilter(GraphPropertyFilter(
        property: 'email',
        operator: GraphFilterOperator.isNotNull,
      ));
      expect(s2, 'n.email IS NOT NULL');
      expect(e2.parameters, isEmpty);
    });

    test('AND / OR compound filters render with parens', () {
      final and = GraphCompoundFilter(GraphFilterCombinator.and, [
        GraphPropertyFilter(
          property: 'a',
          operator: GraphFilterOperator.equal,
          value: 1,
        ),
        GraphPropertyFilter(
          property: 'b',
          operator: GraphFilterOperator.equal,
          value: 2,
        ),
      ]);
      expect(renderFilter(and), '(n.a = \$p0 AND n.b = \$p1)');

      final or = GraphCompoundFilter(GraphFilterCombinator.or, [
        GraphPropertyFilter(
          property: 'a',
          operator: GraphFilterOperator.equal,
          value: 1,
        ),
        GraphPropertyFilter(
          property: 'b',
          operator: GraphFilterOperator.equal,
          value: 2,
        ),
      ]);
      expect(renderFilter(or), '(n.a = \$p0 OR n.b = \$p1)');
    });

    test('NOT renders with parens', () {
      final f = GraphNotFilter(GraphPropertyFilter(
        property: 'deleted',
        operator: GraphFilterOperator.equal,
        value: true,
      ));
      expect(renderFilter(f), 'NOT (n.deleted = \$p0)');
    });
  });

  group('CypherEmitter — full query', () {
    test('pattern + WHERE + ORDER BY + SKIP / LIMIT', () {
      final query = GraphQuery<User>(
        pattern: GraphPattern<User>.build((_) {}, variable: 'u'),
      )
          .where((u) => u['age'].greaterThan(21))
          .orderByProperty('name')
          .orderByProperty('age', direction: GraphSortDirection.descending)
          .offsetBy(10)
          .limitTo(5);

      final stmt = emitQuery(query);
      expect(
        stmt.cypher,
        'MATCH (u:User) WHERE u.age > \$p0 RETURN u '
        'ORDER BY u.name ASC, u.age DESC SKIP \$p1 LIMIT \$p2',
      );
      expect(stmt.parameters, {
        'p0': 21,
        'p1': 10,
        'p2': 5,
      });
    });

    test('chained where clauses AND together', () {
      final query = GraphQuery<User>(
        pattern: GraphPattern<User>.build((_) {}, variable: 'u'),
      )
          .where((u) => u['age'].greaterThan(21))
          .where((u) => u['name'].equalTo('alice'));
      final stmt = emitQuery(query);
      expect(
        stmt.cypher,
        contains('WHERE (u.age > \$p0 AND u.name = \$p1)'),
      );
      expect(stmt.parameters, {'p0': 21, 'p1': 'alice'});
    });

    test('no filter / no order / no limit emits a bare RETURN', () {
      final query = GraphQuery<User>(
        pattern: GraphPattern<User>.build((_) {}, variable: 'u'),
      );
      expect(emitQuery(query).cypher, 'MATCH (u:User) RETURN u');
    });

    test('parameter binding survives nested compound filters', () {
      final query = GraphQuery<User>(
        pattern: GraphPattern<User>.build((_) {}, variable: 'u'),
      ).where(
        (u) => u['age']
            .lessThan(18)
            .or(u['age'].greaterThan(65))
            .and(u['name'].notEqualTo('admin')),
      );
      final stmt = emitQuery(query);
      // Distinct param keys for each value.
      expect(stmt.parameters.keys.toList(), ['p0', 'p1', 'p2']);
      expect(stmt.parameters.values.toList(), [18, 65, 'admin']);
    });
  });

  group('CypherEmitter — identifier escaping', () {
    test('safe identifiers emit bare', () {
      final pattern = GraphPattern<User>.build((_) {}, variable: 'u');
      expect(emitPattern(pattern).cypher, isNot(contains('`')));
    });

    test('label with hyphen gets backtick-quoted', () {
      final pattern = GraphPattern<User>.build(
        (_) {},
        variable: 'n',
        label: GraphLabel('Active-User'),
      );
      expect(emitPattern(pattern).cypher, contains('(n:`Active-User`)'));
    });

    test('property with dot in name gets backtick-quoted in WHERE', () {
      final f = GraphPropertyFilter(
        property: 'meta.legacy',
        operator: GraphFilterOperator.equal,
        value: true,
      );
      expect(
        CypherEmitter().emitFilter(f),
        'n.`meta.legacy` = \$p0',
      );
    });
  });
}
