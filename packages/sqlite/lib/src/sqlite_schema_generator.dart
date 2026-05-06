import 'package:conduit_core/conduit_core.dart';

import 'sqlite_sql_dialect.dart';

/// Schema-generation logic for SQLite, parallel to
/// `PostgreSQLSchemaGenerator` in `package:conduit_postgresql`. Both will
/// move to a shared `SqlSchemaGenerator` in `package:conduit_core` once
/// at least three SQL backends exist (the right number for an
/// abstraction); for now the duplication is intentional and bounded.
///
/// **Limitations.** SQLite's `ALTER TABLE` only supports `ADD COLUMN`,
/// `RENAME TO`, `RENAME COLUMN` (3.25+), and `DROP COLUMN` (3.35+). It
/// has no `ALTER COLUMN` for nullability, default value, type, or
/// uniqueness. Such operations require the documented "create temp
/// table + copy + drop + rename" pattern, which this generator does
/// **not** implement in v0 — it throws `UnsupportedError` instead. Apps
/// that need column alterations against SQLite should run those
/// migrations against Postgres in a CI step or implement the rebuild
/// path manually.
mixin SqliteSchemaGenerator {
  SqlDialect get dialect => const SqliteSqlDialect();

  String get versionTableName => dialect.versionTableName;

  List<String> createTable(SchemaTable table, {bool isTemporary = false}) {
    final commands = <String>[];

    final columnString = table.columns.map(_columnStringForColumn).join(",");
    commands.add(
      "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} ($columnString)",
    );

    final indexCommands = table.columns
        .where(
          (col) => col.isIndexed! && !col.isPrimaryKey!,
        )
        .map((col) => addIndexToColumn(table, col))
        .expand((commands) => commands);
    commands.addAll(indexCommands);

    if (table.uniqueColumnSet != null) {
      commands.addAll(addTableUniqueColumnSet(table));
    }

    return commands;
  }

  List<String> renameTable(SchemaTable table, String name) {
    return ["ALTER TABLE ${table.name} RENAME TO $name"];
  }

  List<String> deleteTable(SchemaTable table) {
    return ["DROP TABLE ${table.name}"];
  }

  List<String> addTableUniqueColumnSet(SchemaTable table) {
    final colNames = table.uniqueColumnSet!
        .map((name) => _columnNameForColumn(table[name]!))
        .join(",");
    return [
      "CREATE UNIQUE INDEX ${table.name}_unique_idx ON ${table.name} ($colNames)"
    ];
  }

  List<String> deleteTableUniqueColumnSet(SchemaTable table) {
    return ["DROP INDEX IF EXISTS ${table.name}_unique_idx"];
  }

  List<String> addColumn(
    SchemaTable table,
    SchemaColumn column, {
    String? unencodedInitialValue,
  }) {
    final commands = <String>[];

    if (unencodedInitialValue != null) {
      // SQLite supports ADD COLUMN with a DEFAULT, but not a subsequent
      // DROP DEFAULT. Mirror the Postgres path's intent by emitting just
      // the ADD with a DEFAULT — the value sticks. Docs note the
      // divergence.
      column.defaultValue = unencodedInitialValue;
      commands.add(
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}",
      );
    } else {
      commands.add(
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}",
      );
    }

    if (column.isIndexed!) {
      commands.addAll(addIndexToColumn(table, column));
    }

    return commands;
  }

  List<String> deleteColumn(SchemaTable table, SchemaColumn column) {
    // Available since SQLite 3.35 (2021); package:sqlite3 ships a newer
    // build, so this is fine.
    return [
      "ALTER TABLE ${table.name} DROP COLUMN ${_columnNameForColumn(column)}"
    ];
  }

  List<String> renameColumn(
    SchemaTable table,
    SchemaColumn column,
    String name,
  ) {
    return [
      "ALTER TABLE ${table.name} "
      "RENAME COLUMN ${_columnNameForColumn(column)} TO $name"
    ];
  }

  List<String> alterColumnNullability(
    SchemaTable table,
    SchemaColumn column,
    String? unencodedInitialValue,
  ) {
    throw UnsupportedError(
      "alterColumnNullability against SQLite requires a table-rebuild "
      "(create temp + copy + rename); not implemented in v0. Run this "
      "migration against Postgres or write the rebuild manually.",
    );
  }

  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) {
    throw UnsupportedError(
      "alterColumnUniqueness against SQLite requires a table-rebuild; "
      "not implemented in v0.",
    );
  }

  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) {
    throw UnsupportedError(
      "alterColumnDefaultValue against SQLite requires a table-rebuild; "
      "not implemented in v0.",
    );
  }

  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) {
    throw UnsupportedError(
      "alterColumnDeleteRule against SQLite requires a table-rebuild "
      "(SQLite enforces foreign keys via PRAGMA foreign_keys; rule "
      "changes need column re-creation). Not implemented in v0.",
    );
  }

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) {
    return [
      "CREATE INDEX ${dialect.indexName(table.name ?? '', _columnNameForColumn(column))} "
      "ON ${table.name} (${_columnNameForColumn(column)})"
    ];
  }

  List<String> renameIndex(
    SchemaTable table,
    SchemaColumn column,
    String newIndexName,
  ) {
    // SQLite has no ALTER INDEX RENAME — drop + recreate is the
    // documented pattern.
    final existing = dialect.indexName(
      table.name ?? '',
      _columnNameForColumn(column),
    );
    return [
      "DROP INDEX $existing",
      "CREATE INDEX $newIndexName ON ${table.name} (${_columnNameForColumn(column)})",
    ];
  }

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    return [
      "DROP INDEX ${dialect.indexName(table.name ?? '', _columnNameForColumn(column))}"
    ];
  }

  // -- helpers ---------------------------------------------------------------

  String _columnStringForColumn(SchemaColumn col) {
    final elements = [_columnNameForColumn(col), _columnTypeForColumn(col)];
    if (col.isPrimaryKey!) {
      // INTEGER PRIMARY KEY is SQLite's auto-increment idiom (aliased to
      // ROWID); the explicit AUTOINCREMENT keyword is rarely needed.
      elements.add("PRIMARY KEY");
    } else {
      elements.add(col.isNullable! ? "NULL" : "NOT NULL");
      if (col.defaultValue != null) {
        elements.add("DEFAULT ${col.defaultValue}");
      }
      if (col.isUnique!) {
        elements.add("UNIQUE");
      }
    }
    return elements.join(" ");
  }

  String _columnNameForColumn(SchemaColumn column) {
    if (column.relatedColumnName != null) {
      return "${column.name}_${column.relatedColumnName}";
    }
    return column.name;
  }

  String? _columnTypeForColumn(SchemaColumn t) {
    final ts = t.typeString;
    if (ts == null) return null;
    return dialect.columnDefinitionType(
      ts,
      autoincrement: t.autoincrement ?? false,
    );
  }

  SchemaTable get versionTable {
    return SchemaTable(versionTableName, [
      SchemaColumn.empty()
        ..name = "versionNumber"
        ..type = ManagedPropertyType.integer
        ..isUnique = true,
      SchemaColumn.empty()
        ..name = "dateOfUpgrade"
        ..type = ManagedPropertyType.datetime,
    ]);
  }
}
