// Unit tests for the G3 filter/sort/pagination arg generation in
// `SchemaBuilder`. The G2 derivation tests cover the no-flag default;
// these tests assert what gets emitted when the flags flip on.

import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import '../fixtures/blog_model.dart';

void main() {
  late ManagedDataModel dataModel;

  setUpAll(() {
    dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
  });

  group('default (no flags) — backward compatibility with G2', () {
    test('list-all fields take zero arguments', () {
      final schema = SchemaBuilder().fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      expect(users.inputs, isEmpty);
    });
  });

  group('generateFilterArgs', () {
    test('list-all fields gain a where: arg', () {
      final schema = SchemaBuilder(generateFilterArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final whereArg = users.inputs.firstWhere((i) => i.name == 'where');
      expect(whereArg.type, isA<GraphQLInputObjectType>());
      expect((whereArg.type as GraphQLInputObjectType).name, equals('UserFilter'));
    });

    test('UserFilter input has one field per non-transient attribute', () {
      final schema = SchemaBuilder(generateFilterArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final filter = (users.inputs.firstWhere((i) => i.name == 'where').type)
          as GraphQLInputObjectType;
      final names = filter.inputFields.map((f) => f.name).toSet();
      // displayName is transient -> excluded.
      // rawName is input-only transient -> excluded.
      // Persisted attributes: id, email, firstName, lastName, isActive, createdAt.
      expect(
          names, equals({'id', 'email', 'firstName', 'lastName', 'isActive', 'createdAt'}));
    });

    test('Each filter field is a <Scalar>Predicate input', () {
      final schema = SchemaBuilder(generateFilterArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final filter = (users.inputs.firstWhere((i) => i.name == 'where').type)
          as GraphQLInputObjectType;
      final emailField = filter.inputFields.firstWhere((f) => f.name == 'email');
      expect(emailField.type, isA<GraphQLInputObjectType>());
      expect(
        (emailField.type as GraphQLInputObjectType).name,
        equals('StringPredicate'),
      );
    });

    test('StringPredicate carries eq/ne/gt/gte/lt/lte/in/notIn/like/isNull',
        () {
      final schema = SchemaBuilder(generateFilterArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final filter = (users.inputs.firstWhere((i) => i.name == 'where').type)
          as GraphQLInputObjectType;
      final emailPredicate =
          filter.inputFields.firstWhere((f) => f.name == 'email').type
              as GraphQLInputObjectType;
      final ops = emailPredicate.inputFields.map((f) => f.name).toSet();
      expect(
        ops,
        containsAll(
          {'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'notIn', 'like', 'isNull'},
        ),
      );
    });

    test('non-string scalars omit the like predicate', () {
      final schema = SchemaBuilder(generateFilterArgs: true)
          .fromManagedDataModel(dataModel);
      final posts = schema.queryType!.fields.firstWhere((f) => f.name == 'posts');
      final filter = (posts.inputs.firstWhere((i) => i.name == 'where').type)
          as GraphQLInputObjectType;
      final ratingPredicate =
          filter.inputFields.firstWhere((f) => f.name == 'rating').type
              as GraphQLInputObjectType;
      final ops = ratingPredicate.inputFields.map((f) => f.name).toSet();
      expect(ops.contains('like'), isFalse);
      // Other ops still present.
      expect(ops, containsAll({'eq', 'ne', 'gt', 'in', 'isNull'}));
    });
  });

  group('generateSortArgs', () {
    test('list-all fields gain an orderBy: arg', () {
      final schema = SchemaBuilder(generateSortArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final orderArg = users.inputs.firstWhere((i) => i.name == 'orderBy');
      // Type is `[UserSortInput!]`
      expect(orderArg.type, isA<GraphQLListType>());
    });

    test('UserSortInput has field: enum and direction: enum', () {
      final schema = SchemaBuilder(generateSortArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final orderArg = users.inputs.firstWhere((i) => i.name == 'orderBy');
      final innerInput = ((orderArg.type as GraphQLListType).ofType
              as GraphQLNonNullableType)
          .ofType as GraphQLInputObjectType;
      expect(innerInput.name, equals('UserSortInput'));
      final fieldField =
          innerInput.inputFields.firstWhere((f) => f.name == 'field');
      // The wrapped non-null enum on `field`.
      expect(fieldField.type, isA<GraphQLNonNullableType>());
      final innerFieldType =
          (fieldField.type as GraphQLNonNullableType).ofType
              as GraphQLEnumType<dynamic>;
      expect(innerFieldType.name, equals('UserSortField'));

      final dirField =
          innerInput.inputFields.firstWhere((f) => f.name == 'direction');
      final innerDirType = (dirField.type as GraphQLNonNullableType).ofType
          as GraphQLEnumType<dynamic>;
      expect(innerDirType.name, equals('SortDirection'));
      expect(innerDirType.values.map((v) => v.name).toSet(),
          equals({'ASC', 'DESC'}));
    });

    test('UserSortField has a value per non-transient attribute', () {
      final schema = SchemaBuilder(generateSortArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final orderArg = users.inputs.firstWhere((i) => i.name == 'orderBy');
      final innerInput = ((orderArg.type as GraphQLListType).ofType
              as GraphQLNonNullableType)
          .ofType as GraphQLInputObjectType;
      final fieldField =
          innerInput.inputFields.firstWhere((f) => f.name == 'field');
      final fieldEnum =
          (fieldField.type as GraphQLNonNullableType).ofType
              as GraphQLEnumType<dynamic>;
      final names = fieldEnum.values.map((v) => v.name).toSet();
      expect(
        names,
        equals({'id', 'email', 'firstName', 'lastName', 'isActive', 'createdAt'}),
      );
    });
  });

  group('generatePaginationArgs', () {
    test('list-all fields gain limit + offset', () {
      final schema = SchemaBuilder(generatePaginationArgs: true)
          .fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final names = users.inputs.map((i) => i.name).toSet();
      expect(names, containsAll({'limit', 'offset'}));
      final limit = users.inputs.firstWhere((i) => i.name == 'limit');
      expect(limit.type.name, equals('Int'));
    });
  });

  group('all flags together', () {
    test('list-all fields carry where, orderBy, limit, offset', () {
      final schema = SchemaBuilder(
        generateFilterArgs: true,
        generateSortArgs: true,
        generatePaginationArgs: true,
      ).fromManagedDataModel(dataModel);
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final names = users.inputs.map((i) => i.name).toSet();
      expect(names, equals({'where', 'orderBy', 'limit', 'offset'}));
    });
  });

  group('resolver hooks', () {
    test('attributeResolver hook fires per attribute and the closure is '
        'attached to the emitted field', () {
      final hookedAttrs = <String>[];
      GraphQLFieldResolver<Object?, Object?>? attrHook(
          ManagedAttributeDescription attr) {
        hookedAttrs.add(attr.name);
        return (Object? p, Map<String, dynamic> a) => 'sentinel';
      }

      final schema = SchemaBuilder(attributeResolver: attrHook)
          .fromManagedDataModel(dataModel);
      // Should have been invoked at least once per non-skipped attr.
      expect(hookedAttrs, isNotEmpty);

      // Spot-check: the User.email field's resolve callback is non-null.
      final userType =
          (schema.queryType!.fields.firstWhere((f) => f.name == 'users').type
                  as GraphQLNonNullableType)
              .ofType as GraphQLListType;
      final userInner =
          (userType.ofType as GraphQLNonNullableType).ofType as GraphQLObjectType;
      final email = userInner.fields.firstWhere((f) => f.name == 'email');
      expect(email.resolve, isNotNull);
    });

    test('queryListResolver hook attaches to plural fields', () {
      final hookedEntities = <String>[];
      GraphQLFieldResolver<Object?, Object?>? listHook(ManagedEntity e) {
        hookedEntities.add(e.name);
        return (Object? p, Map<String, dynamic> a) => const [];
      }

      final schema = SchemaBuilder(queryListResolver: listHook)
          .fromManagedDataModel(dataModel);
      expect(hookedEntities, contains('User'));
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      expect(users.resolve, isNotNull);
    });

    test('queryByPkResolver hook attaches to singular fields', () {
      final schema = SchemaBuilder(queryByPkResolver: (e) =>
              (Object? p, Map<String, dynamic> a) => null)
          .fromManagedDataModel(dataModel);
      final user = schema.queryType!.fields.firstWhere((f) => f.name == 'user');
      expect(user.resolve, isNotNull);
    });

    test('relationshipResolver hook attaches to relationship fields', () {
      final hookedRels = <String>[];
      GraphQLFieldResolver<Object?, Object?>? relHook(
          ManagedRelationshipDescription r) {
        hookedRels.add('${r.entity.name}.${r.name}');
        return (Object? p, Map<String, dynamic> a) => null;
      }

      final schema = SchemaBuilder(relationshipResolver: relHook)
          .fromManagedDataModel(dataModel);
      // Walk to a concrete relationship field.
      final users = schema.queryType!.fields.firstWhere((f) => f.name == 'users');
      final userType =
          ((users.type as GraphQLNonNullableType).ofType as GraphQLListType);
      final userInner =
          (userType.ofType as GraphQLNonNullableType).ofType as GraphQLObjectType;
      final posts = userInner.fields.firstWhere((f) => f.name == 'posts');
      expect(posts.resolve, isNotNull);
      expect(hookedRels, contains('User.posts'));
    });
  });
}
