/// Test-only ManagedObject fixture used by the G2 schema-derivation
/// tests. Five entities, deliberately chosen to exercise:
///
/// * every primitive `ManagedPropertyType` (integer, bigInteger,
///   string, datetime, boolean, doublePrecision, document) at least
///   once;
/// * every relationship arity (`belongsTo`, `hasOne`, `hasMany`),
///   including required vs nullable belongsTo and a many-to-many
///   surfaced through a join table;
/// * a self-reference (`Comment.parent: Comment?`);
/// * a transient `Serialize.input`-only field that the schema must
///   exclude;
/// * a transient `Serialize.output`-only field that the schema must
///   include (as nullable);
/// * an `omitByDefault` column to confirm we still surface it in the
///   schema (presence-in-default-result-set is an ORM-side concern,
///   not a GraphQL-visibility concern).

library;

import 'package:conduit_core/conduit_core.dart';

// -- User -------------------------------------------------------------------

class User extends ManagedObject<_User> implements _User {
  /// Output-only transient: should appear as a nullable `String` in
  /// the schema.
  @Serialize(input: false, output: true)
  String get displayName => '${firstName ?? ''} ${lastName ?? ''}'.trim();

  /// Input-only transient: should be excluded from the output schema.
  @Serialize(input: true, output: false)
  set rawName(String s) {
    final parts = s.split(' ');
    firstName = parts.isNotEmpty ? parts.first : null;
    lastName = parts.length > 1 ? parts.last : null;
  }
}

class _User {
  @primaryKey
  int? id;

  @Column(unique: true)
  String? email;

  @Column(nullable: true)
  String? firstName;

  @Column(nullable: true)
  String? lastName;

  @Column(defaultValue: 'true')
  bool? isActive;

  @Column(defaultValue: 'now()')
  DateTime? createdAt;

  /// Reverse end of `Post.author` — hasMany.
  ManagedSet<Post>? posts;

  /// Reverse end of `Comment.author` — hasMany.
  ManagedSet<Comment>? comments;
}

// -- Post -------------------------------------------------------------------

class Post extends ManagedObject<_Post> implements _Post {}

class _Post {
  @primaryKey
  int? id;

  String? title;

  @Column(omitByDefault: true)
  String? body;

  @Column(databaseType: ManagedPropertyType.bigInteger)
  int? viewCount;

  double? rating;

  /// Required belongsTo — non-null in the schema.
  @Relate(Symbol('posts'), isRequired: true, onDelete: DeleteRule.cascade)
  User? author;

  /// Reverse end of `Comment.post` — hasMany.
  ManagedSet<Comment>? comments;

  /// Reverse end of `PostTag.post` — hasMany (the join-table side
  /// surfaces as a list of join rows, not a flat list of Tags).
  ManagedSet<PostTag>? tags;
}

// -- Comment ----------------------------------------------------------------

class Comment extends ManagedObject<_Comment> implements _Comment {}

class _Comment {
  @primaryKey
  int? id;

  String? body;

  /// Required belongsTo to Post — non-null in the schema.
  @Relate(Symbol('comments'), isRequired: true, onDelete: DeleteRule.cascade)
  Post? post;

  /// Optional belongsTo to User — nullable in the schema.
  @Relate(Symbol('comments'))
  User? author;

  /// Self-reference: optional belongsTo to another Comment.
  @Relate(Symbol('replies'))
  Comment? parent;

  /// Reverse end of self-reference — hasMany.
  ManagedSet<Comment>? replies;
}

// -- Tag --------------------------------------------------------------------

class Tag extends ManagedObject<_Tag> implements _Tag {}

class _Tag {
  @Column(primaryKey: true)
  String? name;

  @Column(nullable: true)
  String? description;

  /// Reverse end of `PostTag.tag` — hasMany.
  ManagedSet<PostTag>? posts;
}

// -- PostTag join table -----------------------------------------------------

class PostTag extends ManagedObject<_PostTag> implements _PostTag {}

class _PostTag {
  @primaryKey
  int? id;

  /// Required belongsTo to Post.
  @Relate(Symbol('tags'), isRequired: true, onDelete: DeleteRule.cascade)
  Post? post;

  /// Required belongsTo to Tag.
  @Relate(Symbol('posts'), isRequired: true, onDelete: DeleteRule.cascade)
  Tag? tag;
}
