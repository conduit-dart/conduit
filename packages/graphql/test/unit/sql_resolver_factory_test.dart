// Unit tests for SqlResolverFactory's argument-lowering surface.
//
// These exercise the path that walks GraphQL `where:`, `orderBy:`,
// `limit:`, and `offset:` arguments and turns them into Conduit
// `QueryExpression` / `QuerySortDescriptor` / `fetchLimit` / `offset`
// state. They run without a database — we instantiate
// `Query.forEntity` against an unconnected store and inspect the
// QueryMixin's internal state via cast.
//
// The integration tests in `test/integration/` cover the actual
// SQL-execution path against real backends.

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';
import 'package:test/test.dart';

import '../fixtures/blog_model.dart';

late ManagedDataModel dataModel;
late ManagedContext context;
late SqlResolverFactory factory;

/// Builds a `Query.forEntity` for [type] and runs [args] through the
/// real factory's argument-lowering path (without executing it).
/// Returns the populated query for state assertions.
Query buildQueryWithArgs(Type type, Map<String, dynamic> args) {
  final entity = dataModel.entityForType(type);
  final query = Query.forEntity(entity, context);
  factory.applyListArgs(query, entity, args);
  return query;
}

void main() {
  setUpAll(() {
    dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
    // Use an unconnected Postgres store: we never call its query
    // methods, just instantiate `Query.forEntity` against it. The
    // QueryMixin state we inspect is dialect-independent.
    final store = PostgreSQLPersistentStore(
      'test',
      'test',
      'localhost',
      5432,
      'test',
    );
    context = ManagedContext(dataModel, store);
    factory = SqlResolverFactory(context);
  });

  tearDownAll(() async {
    await context.close();
  });

  group('listResolverFor argument lowering', () {
    test('limit + offset land on Query.fetchLimit / Query.offset',
        () async {
      final query = buildQueryWithArgs(User, {
        'limit': 10,
        'offset': 5,
      });
      expect(query.fetchLimit, equals(10));
      expect(query.offset, equals(5));
    });

    test('orderBy ASC builds a QuerySortDescriptor with ascending order',
        () async {
      final query = buildQueryWithArgs(User, {
        'orderBy': [
          {'field': 'createdAt', 'direction': 'ASC'},
        ],
      });
      final mixin = query as QueryMixin;
      expect(mixin.sortDescriptors, hasLength(1));
      expect(mixin.sortDescriptors.first.key, equals('createdAt'));
      expect(
        mixin.sortDescriptors.first.order,
        equals(QuerySortOrder.ascending),
      );
    });

    test('orderBy DESC builds a descending QuerySortDescriptor',
        () async {
      final query = buildQueryWithArgs(User, {
        'orderBy': [
          {'field': 'createdAt', 'direction': 'DESC'},
        ],
      });
      final mixin = query as QueryMixin;
      expect(
        mixin.sortDescriptors.first.order,
        equals(QuerySortOrder.descending),
      );
    });

    test('multi-entry orderBy preserves precedence', () async {
      final query = buildQueryWithArgs(User, {
        'orderBy': [
          {'field': 'createdAt', 'direction': 'DESC'},
          {'field': 'email', 'direction': 'ASC'},
        ],
      });
      final mixin = query as QueryMixin;
      expect(mixin.sortDescriptors, hasLength(2));
      expect(mixin.sortDescriptors[0].key, equals('createdAt'));
      expect(mixin.sortDescriptors[1].key, equals('email'));
    });

    test('orderBy on unknown field is silently dropped (defensive)',
        () async {
      final query = buildQueryWithArgs(User, {
        'orderBy': [
          {'field': 'doesNotExist', 'direction': 'ASC'},
        ],
      });
      final mixin = query as QueryMixin;
      expect(mixin.sortDescriptors, isEmpty);
    });
  });

  group('listResolverFor predicate lowering', () {
    test('eq lowers to a ComparisonExpression(equalTo) on numeric attrs',
        () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'rating': {'eq': 4.5},
        },
      });
      final mixin = query as QueryMixin;
      expect(mixin.expressions, hasLength(1));
      final expr = mixin.expressions.first.expression;
      expect(expr, isA<ComparisonExpression>());
      expect((expr as ComparisonExpression).operator,
          equals(PredicateOperator.equalTo));
      expect(expr.value, equals(4.5));
    });

    test('eq on string lowers to a StringExpression(equals)', () async {
      final query = buildQueryWithArgs(User, {
        'where': {
          'email': {'eq': 'a@b.com'},
        },
      });
      final mixin = query as QueryMixin;
      final expr = mixin.expressions.first.expression;
      expect(expr, isA<StringExpression>());
      expect(
        (expr as StringExpression).operator,
        equals(PredicateStringOperator.equals),
      );
    });

    test('ne lowers to PredicateOperator.notEqual', () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'rating': {'ne': 1.0},
        },
      });
      final expr =
          (query as QueryMixin).expressions.first.expression
              as ComparisonExpression;
      expect(expr.operator, equals(PredicateOperator.notEqual));
    });

    test('gt / gte / lt / lte lower to the right comparison operators',
        () async {
      final cases = {
        'gt': PredicateOperator.greaterThan,
        'gte': PredicateOperator.greaterThanEqualTo,
        'lt': PredicateOperator.lessThan,
        'lte': PredicateOperator.lessThanEqualTo,
      };
      for (final entry in cases.entries) {
        final query = buildQueryWithArgs(Post, {
          'where': {
            'rating': {entry.key: 3.0},
          },
        });
        final expr = (query as QueryMixin).expressions.first.expression;
        expect(expr, isA<ComparisonExpression>(),
            reason: '${entry.key} must lower to ComparisonExpression');
        expect((expr as ComparisonExpression).operator, equals(entry.value),
            reason: '${entry.key} should map to ${entry.value}');
      }
    });

    test('in lowers to SetMembershipExpression(within: true)', () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'rating': {'in': [3.0, 4.0, 5.0]},
        },
      });
      final expr = (query as QueryMixin).expressions.first.expression;
      expect(expr, isA<SetMembershipExpression>());
      expect((expr as SetMembershipExpression).within, isTrue);
      expect(expr.values, equals([3.0, 4.0, 5.0]));
    });

    test('notIn lowers to SetMembershipExpression(within: false)',
        () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'rating': {'notIn': [1.0, 2.0]},
        },
      });
      final expr = (query as QueryMixin).expressions.first.expression
          as SetMembershipExpression;
      expect(expr.within, isFalse);
    });

    test('like lowers to a StringExpression(contains)', () async {
      final query = buildQueryWithArgs(User, {
        'where': {
          'email': {'like': 'gmail'},
        },
      });
      final expr = (query as QueryMixin).expressions.first.expression
          as StringExpression;
      expect(expr.operator, equals(PredicateStringOperator.contains));
      expect(expr.value, equals('gmail'));
    });

    test('isNull: true lowers to NullCheckExpression(shouldBeNull: true)',
        () async {
      final query = buildQueryWithArgs(User, {
        'where': {
          'firstName': {'isNull': true},
        },
      });
      final expr = (query as QueryMixin).expressions.first.expression
          as NullCheckExpression;
      expect(expr.shouldBeNull, isTrue);
    });

    test('isNull: false lowers to shouldBeNull: false', () async {
      final query = buildQueryWithArgs(User, {
        'where': {
          'firstName': {'isNull': false},
        },
      });
      final expr = (query as QueryMixin).expressions.first.expression
          as NullCheckExpression;
      expect(expr.shouldBeNull, isFalse);
    });

    test('multiple where fields AND together (one expression per field)',
        () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'rating': {'gt': 3.0},
          'title': {'like': 'Foo'},
        },
      });
      final mixin = query as QueryMixin;
      expect(mixin.expressions, hasLength(2));
    });

    test('unknown predicate keys are dropped without throwing',
        () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'rating': {'unknownOp': 1.0},
        },
      });
      expect((query as QueryMixin).expressions, isEmpty);
    });

    test('unknown attribute keys are dropped without throwing',
        () async {
      final query = buildQueryWithArgs(Post, {
        'where': {
          'doesNotExist': {'eq': 1},
        },
      });
      expect((query as QueryMixin).expressions, isEmpty);
    });
  });
}
