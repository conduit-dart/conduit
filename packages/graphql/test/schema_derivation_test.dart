// Structural tests for `SchemaBuilder.fromManagedDataModel`.
//
// These tests verify the *shape* of the derived schema — the type
// list, field list, scalar mapping, nullability matrix, and
// transient-property exclusion. The byte-equality golden test lives
// alongside in `golden_schema_test.dart`; the introspection
// round-trip is in `introspection_round_trip_test.dart`.

// Hide conduit_core's SchemaBuilder (a database-migration helper) so
// the schema-derivation SchemaBuilder from conduit_graphql resolves
// without an `as` prefix.
import 'package:conduit_core/conduit_core.dart' hide SchemaBuilder;
import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:test/test.dart';

import 'fixtures/blog_model.dart';

void main() {
  late ManagedDataModel dataModel;
  late GraphQLSchema schema;

  setUpAll(() {
    dataModel = ManagedDataModel([User, Post, Comment, Tag, PostTag]);
    schema = SchemaBuilder().fromManagedDataModel(dataModel);
  });

  group('5-entity fixture', () {
    test('emits exactly 5 ObjectTypes (one per entity) plus Query', () {
      // Walk Query's fields to discover every reachable ObjectType.
      final reachable = _reachableObjectTypes(schema);
      final entityTypeNames = reachable
          .map((t) => t.name)
          .where((n) => n != 'Query')
          .toSet();
      expect(
        entityTypeNames,
        equals({'User', 'Post', 'Comment', 'Tag', 'PostTag'}),
      );
    });

    test('Query root has 10 fields (5 list + 5 by-pk)', () {
      final query = schema.queryType!;
      expect(query.fields, hasLength(10));

      final names = query.fields.map((f) => f.name).toSet();
      expect(
        names,
        equals({
          // list-all
          'users', 'posts', 'comments', 'tags', 'postTags',
          // by-pk
          'user', 'post', 'comment', 'tag', 'postTag',
        }),
      );
    });

    test('list-all fields are non-null lists of non-null entities', () {
      final query = schema.queryType!;
      final users = query.fields.firstWhere((f) => f.name == 'users');
      expect(users.type.toString(), equals('[User!]!'));

      final posts = query.fields.firstWhere((f) => f.name == 'posts');
      expect(posts.type.toString(), equals('[Post!]!'));
    });

    test('by-pk fields are nullable entity types with non-null pk arg', () {
      final query = schema.queryType!;

      final user = query.fields.firstWhere((f) => f.name == 'user');
      expect(user.type.toString(), equals('User'));
      expect(user.inputs, hasLength(1));
      expect(user.inputs.first.name, equals('id'));
      // Conduit primaryKey lowers to bigInteger, which our default
      // mapping surfaces as String!.
      expect(user.inputs.first.type.toString(), equals('String!'));

      final tag = query.fields.firstWhere((f) => f.name == 'tag');
      // Tag's primary key is a String, not the default bigInteger.
      expect(tag.inputs.first.type.toString(), equals('String!'));
    });
  });

  group('scalar mapping', () {
    test('integer -> Int, doublePrecision -> Float, bigInteger -> String', () {
      final post = _objectByName(schema, 'Post');
      // viewCount is bigInteger; column carries no `nullable: true`,
      // so Conduit defaults to non-nullable -> String!
      final viewCount = post.fields.firstWhere((f) => f.name == 'viewCount');
      expect(viewCount.type.toString(), equals('String!'));

      // rating is double, no @Column, so Conduit defaults to
      // non-nullable -> Float!
      final rating = post.fields.firstWhere((f) => f.name == 'rating');
      expect(rating.type.toString(), equals('Float!'));
    });

    test('datetime -> DateTime, boolean -> Boolean, string -> String', () {
      final user = _objectByName(schema, 'User');

      // createdAt has a defaultValue 'now()', so it's nullable in the
      // schema (because we only mark non-null when defaultValue is
      // null AND isNullable is false).
      final createdAt = user.fields.firstWhere((f) => f.name == 'createdAt');
      expect(createdAt.type.toString(), equals('DateTime'));

      // isActive has a defaultValue 'true' -> nullable in schema.
      final isActive = user.fields.firstWhere((f) => f.name == 'isActive');
      expect(isActive.type.toString(), equals('Boolean'));

      // email has no nullable + no default -> non-null String.
      final email = user.fields.firstWhere((f) => f.name == 'email');
      expect(email.type.toString(), equals('String!'));
    });

    test('primary keys are always non-null', () {
      // bigInteger pk -> String!
      expect(
        _fieldType(schema, 'User', 'id'),
        equals('String!'),
      );
      // String pk -> String!
      expect(
        _fieldType(schema, 'Tag', 'name'),
        equals('String!'),
      );
    });
  });

  group('relationships', () {
    test('hasMany surfaces as [Type!]!', () {
      // User.posts: [Post!]!
      expect(_fieldType(schema, 'User', 'posts'), equals('[Post!]!'));
      // Post.comments: [Comment!]!
      expect(_fieldType(schema, 'Post', 'comments'), equals('[Comment!]!'));
      // Comment.replies (self-reference): [Comment!]!
      expect(_fieldType(schema, 'Comment', 'replies'), equals('[Comment!]!'));
    });

    test('required belongsTo is non-null', () {
      // Post.author -> User!  (Relate(isRequired: true))
      expect(_fieldType(schema, 'Post', 'author'), equals('User!'));
      // Comment.post -> Post!  (Relate(isRequired: true))
      expect(_fieldType(schema, 'Comment', 'post'), equals('Post!'));
      // PostTag.post / PostTag.tag -> Post! / Tag!
      expect(_fieldType(schema, 'PostTag', 'post'), equals('Post!'));
      expect(_fieldType(schema, 'PostTag', 'tag'), equals('Tag!'));
    });

    test('optional belongsTo is nullable', () {
      // Comment.author (no isRequired) -> User
      expect(_fieldType(schema, 'Comment', 'author'), equals('User'));
      // Comment.parent (self-ref, no isRequired) -> Comment
      expect(_fieldType(schema, 'Comment', 'parent'), equals('Comment'));
    });

    test('many-to-many surfaces as a join-table list (no auto-flattening)', () {
      // Post.tags: [PostTag!]! (NOT [Tag!]!) — the schema surfaces
      // join rows verbatim.
      expect(_fieldType(schema, 'Post', 'tags'), equals('[PostTag!]!'));
      expect(_fieldType(schema, 'Tag', 'posts'), equals('[PostTag!]!'));
    });

    test('the same Type instance is shared across both ends of a relationship', () {
      // Deferred-ref correctness: `User.posts` and the `posts` Query
      // root field must point at the *same* Post object-type instance
      // (not a fresh stub). The most direct check is identity equality.
      final postType = _objectByName(schema, 'Post');
      final userPostsField =
          _objectByName(schema, 'User').fields.firstWhere((f) => f.name == 'posts');
      // userPostsField.type is GraphQLNonNullableType(GraphQLListType(GraphQLNonNullableType(Post)))
      final innerListElement =
          ((userPostsField.type as GraphQLNonNullableType).ofType
              as GraphQLListType).ofType;
      final innerEntity =
          (innerListElement as GraphQLNonNullableType).ofType;
      expect(identical(innerEntity, postType), isTrue);
    });
  });

  group('transient properties', () {
    test('output-only transient is included as nullable', () {
      // User.displayName is @Serialize(input: false, output: true)
      // -> appears in schema as nullable String.
      expect(_fieldType(schema, 'User', 'displayName'), equals('String'));
    });

    test('input-only transient is excluded', () {
      // User.rawName is @Serialize(input: true, output: false)
      // -> NOT in the schema.
      final user = _objectByName(schema, 'User');
      final names = user.fields.map((f) => f.name).toSet();
      expect(names.contains('rawName'), isFalse);
    });
  });

  group('custom scalars', () {
    test('DateTime scalar registered and used', () {
      // The DateTime scalar must be reachable through some field.
      final user = _objectByName(schema, 'User');
      final createdAt = user.fields.firstWhere((f) => f.name == 'createdAt');
      // Strip nullable wrapper if present.
      final inner = createdAt.type is GraphQLNonNullableType
          ? (createdAt.type as GraphQLNonNullableType).ofType
          : createdAt.type;
      expect(inner.name, equals('DateTime'));
    });
  });

  group('omitByDefault columns', () {
    test('still appear in the schema (visibility is an ORM concern)', () {
      // Post.body is `@Column(omitByDefault: true)`. Whether the ORM
      // returns it by default is orthogonal to whether the GraphQL
      // schema lists it; the schema must list it so clients can ask
      // for it explicitly.
      expect(_fieldType(schema, 'Post', 'body'), equals('String!'));
    });
  });

  group('SchemaBuilder configuration', () {
    test('bigIntegerAsString=false lowers bigInteger to Int', () {
      final intSchema =
          SchemaBuilder(bigIntegerAsString: false).fromManagedDataModel(dataModel);
      // Now User.id is Int!.
      expect(_fieldType(intSchema, 'User', 'id'), equals('Int!'));
      // viewCount has no `nullable: true`, so it's non-null -> Int!
      expect(_fieldType(intSchema, 'Post', 'viewCount'), equals('Int!'));
    });

    test('throws ArgumentError on empty model', () {
      // Fabricate an "empty" model by abusing tryEntityForType — but
      // ManagedDataModel always demands at least one type. Instead we
      // verify the documented error path with a stub.
      expect(
        () => SchemaBuilder().fromManagedDataModel(_EmptyModel()),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('objectTypeFor (single-entity convenience)', () {
    test('returns a populated type for the given entity', () {
      final entity = dataModel.entityForType(User);
      final type = SchemaBuilder().objectTypeFor(entity);
      expect(type.name, equals('User'));
      // Should at minimum carry the scalar fields.
      final names = type.fields.map((f) => f.name).toSet();
      expect(names.containsAll({'id', 'email', 'createdAt'}), isTrue);
    });
  });
}

// -- Helpers ----------------------------------------------------------------

/// Walks every field of every reachable `GraphQLObjectType` starting
/// from [schema.queryType], collecting the closure of object types.
Set<GraphQLObjectType> _reachableObjectTypes(GraphQLSchema schema) {
  final out = <GraphQLObjectType>{};
  final stack = <GraphQLObjectType>[schema.queryType!];
  while (stack.isNotEmpty) {
    final t = stack.removeLast();
    if (!out.add(t)) continue;
    for (final f in t.fields) {
      final inner = _unwrapObjectType(f.type);
      if (inner != null) stack.add(inner);
    }
  }
  return out;
}

GraphQLObjectType? _unwrapObjectType(GraphQLType type) {
  GraphQLType current = type;
  while (true) {
    if (current is GraphQLObjectType) return current;
    if (current is GraphQLNonNullableType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLListType) {
      current = current.ofType;
      continue;
    }
    return null;
  }
}

GraphQLObjectType _objectByName(GraphQLSchema schema, String name) {
  final found = _reachableObjectTypes(schema).firstWhere(
    (t) => t.name == name,
    orElse: () => throw StateError(
      'Type $name not reachable from schema.queryType',
    ),
  );
  return found;
}

String _fieldType(GraphQLSchema schema, String typeName, String fieldName) {
  final t = _objectByName(schema, typeName);
  final f = t.fields.firstWhere(
    (f) => f.name == fieldName,
    orElse: () => throw StateError(
      'Field $typeName.$fieldName not present in schema',
    ),
  );
  return f.type.toString();
}

/// Empty stand-in to test the empty-model error path without going
/// through the real ManagedDataModel constructor (which has its own
/// "no types" guard). Uses `noSuchMethod` rather than implementing
/// `ManagedDataModel` directly because the real interface drags in
/// `APIComponentDocumenter` from a separate package and we only need
/// `entities` for the test path under exercise.
class _EmptyModel implements ManagedDataModel {
  @override
  Iterable<ManagedEntity> get entities => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in this test');
}
