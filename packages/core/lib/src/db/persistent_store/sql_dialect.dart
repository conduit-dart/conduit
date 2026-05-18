/// Dialect-specific SQL generation surface.
///
/// `PersistentStore` is the framework-facing seam for swapping ORM backends,
/// but most of the *generation* of SQL — column DDL types, parameter
/// placeholder syntax, identifier quoting, naming conventions, table-existence
/// queries, error code translation — varies between SQL backends. A
/// `SqlDialect` instance is the per-backend strategy that handles that
/// generation; backends compose a `PersistentStore` subclass with a
/// `SqlDialect` to land a working backend.
///
/// Defaults on this class lean toward **standard / ANSI SQL** so a subclass
/// only has to override the bits where it diverges. The Postgres
/// implementation in `package:conduit_postgresql` is a useful reference;
/// SQLite and MySQL implementations mostly come down to overriding the
/// type-map, parameter syntax, and version-table name.
///
/// This class is a value: instances should be cheap to construct and
/// allocation-free on the hot path. Concrete implementations should not
/// hold connection state — that lives on the `PersistentStore`.
library;

import 'package:conduit_core/src/db/managed/type.dart';
import 'package:conduit_core/src/db/persistent_store/sql_expression_visitor.dart';
import 'package:conduit_core/src/db/query/expression_ast.dart';

/// Whether a dialect uses named parameters (`@name` / `:name`) or
/// positional ones (`?`). Drives which visitor implementation
/// [SqlDialect.renderExpression] constructs.
enum SqlParameterStyle { named, positional }

abstract class SqlDialect {
  const SqlDialect();

  /// Short name used to suffix the version table and to differentiate
  /// dialects in error messages and logs. e.g. 'postgres', 'sqlite',
  /// 'mysql', 'cockroach'.
  String get name;

  // -- Type mapping -----------------------------------------------------------

  /// Map a Conduit `ManagedPropertyType.toString()` (one of `integer`,
  /// `bigInteger`, `string`, `datetime`, `boolean`, `double`, `document`) to
  /// the dialect-specific column-definition type string.
  ///
  /// Returning `null` signals "not a supported type for this dialect" —
  /// callers handle by raising a clear schema error.
  String? columnDefinitionType(String typeString, {required bool autoincrement});

  // -- Value encoding ---------------------------------------------------------

  /// Coerce a Dart value into the dialect's wire-protocol parameter
  /// form. Used by the dialect-agnostic query builders to wrap values
  /// before they are placed into `executeQuery`'s `substitutionValues`
  /// map.
  ///
  /// Postgres returns a `TypedValue` (from `package:postgres`) so the
  /// driver knows the column's SQL type; SQLite and MySQL just pass
  /// the value through (their drivers infer the type from the bound
  /// Dart value). Returning `Object?` keeps the contract
  /// driver-agnostic — the persistent store's `executeQuery`
  /// implementation knows how to consume the dialect's specific wire
  /// form.
  ///
  /// Default is pass-through, which is the right behavior for
  /// drivers that take Dart values directly. The Postgres dialect
  /// overrides to wrap with `TypedValue`.
  Object? encodeValue(Object? value, ManagedPropertyType? type) => value;

  // -- Parameter placeholder syntax -------------------------------------------

  /// How to refer to a named parameter inside a SQL string. Default is
  /// `@name` (Postgres named-parameter convention). SQLite uses
  /// `:name`; MySQL uses positional `?` (and ignores the supplied
  /// name — see [parameterStyle]).
  String parameterPlaceholder(String name) => '@$name';

  /// Whether this dialect binds parameters by name (a `Map<String,
  /// Object?>` carries the bindings) or by position (a
  /// `List<Object?>` ordered to match `?` placeholders in the SQL).
  /// Defaults to named since that's the historical Conduit
  /// convention.
  SqlParameterStyle get parameterStyle => SqlParameterStyle.named;

  /// Render a [SqlExpression] AST into a [RenderedExpression] using
  /// the dialect's preferred parameter style. The result carries
  /// either a named-parameter map (for [SqlParameterStyle.named]) or
  /// a positional-parameter list (for [SqlParameterStyle.positional]).
  ///
  /// Backends call this when they recognize that a [QueryPredicate]
  /// has an attached `expression` AST and want dialect-correct
  /// placeholders. The base implementation creates the appropriate
  /// visitor and walks the AST; dialects with truly custom rendering
  /// needs may override.
  RenderedExpression renderExpression(SqlExpression expression) {
    switch (parameterStyle) {
      case SqlParameterStyle.named:
        return NamedSqlExpressionVisitor(this).render(expression);
      case SqlParameterStyle.positional:
        return PositionalSqlExpressionVisitor(this).render(expression);
    }
  }

  // -- Comparison + matching operators ----------------------------------------

  /// Operator for case-sensitive pattern match. Standard SQL: `LIKE`.
  String get caseSensitiveLikeOperator => 'LIKE';

  /// Operator for case-insensitive pattern match. Standard SQL has no
  /// equivalent; SQLite's `LIKE` is case-insensitive by default; MySQL
  /// uses `LIKE` with a case-insensitive collation; Postgres has `ILIKE`.
  /// Default echoes `LIKE`; backends override as needed.
  String get caseInsensitiveLikeOperator => 'LIKE';

  /// Standard SQL: `IS NULL`. Postgres also accepts the shorthand `ISNULL`
  /// — which the current PG path uses. Override if backend differs.
  String get isNullOperator => 'IS NULL';
  String get isNotNullOperator => 'IS NOT NULL';

  // -- DDL conventions --------------------------------------------------------

  /// Standard SQL: `ALTER TABLE`. Postgres uses `ALTER TABLE ONLY` for
  /// constraint modifications to avoid recursing into inheritance children
  /// — that's the only known divergence.
  String get alterTableForConstraintModification => 'ALTER TABLE';

  /// Suggested name for a unique constraint backing a single column.
  String uniqueKeyName(String tableName, String columnName) =>
      '${tableName}_${columnName}_key';

  /// Suggested name for a foreign-key constraint.
  String foreignKeyName(String tableName, String columnName) =>
      '${tableName}_${columnName}_fkey';

  /// Suggested name for an index on a single column.
  String indexName(String tableName, String columnName) =>
      '${tableName}_${columnName}_idx';

  // -- Schema-version bookkeeping --------------------------------------------

  /// The table conduit creates to track applied migration versions.
  /// Suffixed by [name] so concurrent multi-dialect applications don't
  /// collide on the same physical database (rare, but cheap insurance).
  String get versionTableName => '_conduit_version_$name';

  /// Returns SQL that, when executed with a single named parameter
  /// `tableName`, yields one row whose first column is non-null when the
  /// table exists.
  ///
  /// Postgres uses `SELECT to_regclass(@tableName:text)`; SQLite reads
  /// `sqlite_master`; MySQL queries `information_schema.tables`. Each
  /// dialect's exact form is its own concern.
  String tableExistsQuery();

  // -- LIKE-pattern escaping --------------------------------------------------

  /// Escapes wildcard characters in a user-supplied LIKE pattern so they
  /// match literally. Default escapes `\\`, `%`, and `_` with a leading
  /// backslash, which is the Postgres / SQLite / MySQL convention when
  /// the default ESCAPE character is in effect.
  String escapeLikePattern(String input) {
    return input.replaceAllMapped(
      RegExp(r'(\\|%|_)'),
      (m) => '\\${m[0]}',
    );
  }
}
