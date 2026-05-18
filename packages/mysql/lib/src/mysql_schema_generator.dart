import 'package:conduit_core/conduit_core.dart';

import 'mysql_sql_dialect.dart';

/// Schema-generation logic for MySQL / MariaDB. Parallel to the
/// SQLite + Postgres generators; the three diverge enough that a
/// shared `SqlSchemaGenerator` in `conduit_core` only becomes
/// worthwhile once a fourth backend lands. For now, copy + dialect
/// hooks.
///
/// **Limitations.**
///   - `renameTable` and `renameIndex` are emitted directly via
///     `RENAME TABLE` / `ALTER TABLE … RENAME INDEX`. Both work in
///     MySQL 5.7+ and MariaDB 10+.
///   - `alterColumnNullability` uses `MODIFY COLUMN` — MySQL doesn't
///     have a discrete `ALTER COLUMN SET/DROP NOT NULL`; you re-state
///     the entire column definition. We re-derive the type from the
///     [SqlDialect] so the new column DDL stays consistent with
///     `createTable`'s output.
///   - `alterColumnUniqueness` toggles a `UNIQUE INDEX` rather than a
///     unique constraint — MySQL implements unique constraints via
///     unique indexes anyway, and `DROP INDEX` is the cleanest
///     reversal.
mixin MysqlSchemaGenerator {
  /// Override in concrete stores if a customized dialect is needed
  /// (e.g., a MariaDB-only divergence, currently unused).
  SqlDialect get dialect => const MysqlSqlDialect();

  String get versionTableName => dialect.versionTableName;

  List<String> createTable(SchemaTable table, {bool isTemporary = false}) {
    final commands = <String>[];

    final columnString = table.columns.map(_columnStringForColumn).join(",");
    commands.add(
      "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} ($columnString)",
    );

    final indexCommands = table.columns
        .where((col) => col.isIndexed! && !col.isPrimaryKey!)
        .map((col) => addIndexToColumn(table, col))
        .expand((commands) => commands);
    commands.addAll(indexCommands);

    commands.addAll(
      table.columns
          .where((sc) => sc.isForeignKey)
          .map((col) => _addConstraintsForColumn(table.name, col))
          .expand((commands) => commands),
    );

    if (table.uniqueColumnSet != null) {
      commands.addAll(addTableUniqueColumnSet(table));
    }

    return commands;
  }

  List<String> renameTable(SchemaTable table, String name) {
    return ["RENAME TABLE ${table.name} TO $name"];
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
    return ["DROP INDEX ${table.name}_unique_idx ON ${table.name}"];
  }

  List<String> addColumn(
    SchemaTable table,
    SchemaColumn column, {
    String? unencodedInitialValue,
  }) {
    final commands = <String>[];

    if (unencodedInitialValue != null) {
      column.defaultValue = unencodedInitialValue;
      commands.add(
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}",
      );
      // Drop the default in a follow-up so the value sticks for
      // existing rows but new inserts don't auto-fill it.
      commands.add(
        "ALTER TABLE ${table.name} ALTER COLUMN "
        "${_columnNameForColumn(column)} DROP DEFAULT",
      );
    } else {
      commands.add(
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}",
      );
    }

    if (column.isIndexed!) {
      commands.addAll(addIndexToColumn(table, column));
    }

    if (column.isForeignKey) {
      commands.addAll(_addConstraintsForColumn(table.name, column));
    }

    return commands;
  }

  List<String> deleteColumn(SchemaTable table, SchemaColumn column) {
    return [
      "ALTER TABLE ${table.name} DROP COLUMN ${_columnNameForColumn(column)}"
    ];
  }

  List<String> renameColumn(
    SchemaTable table,
    SchemaColumn column,
    String name,
  ) {
    // MySQL 8.0+ / MariaDB 10.5+ support ALTER TABLE ... RENAME COLUMN.
    // Older versions need CHANGE COLUMN with the full definition; we
    // emit RENAME COLUMN and let the user know in docs.
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
    if (column.isNullable!) {
      return [
        "ALTER TABLE ${table.name} MODIFY COLUMN "
        "${_columnNameForColumn(column)} ${_columnTypeForColumn(column)} NULL"
      ];
    } else {
      final commands = <String>[];
      if (unencodedInitialValue != null) {
        commands.add(
          "UPDATE ${table.name} SET ${_columnNameForColumn(column)}="
          "$unencodedInitialValue WHERE ${_columnNameForColumn(column)} IS NULL",
        );
      }
      commands.add(
        "ALTER TABLE ${table.name} MODIFY COLUMN "
        "${_columnNameForColumn(column)} ${_columnTypeForColumn(column)} NOT NULL",
      );
      return commands;
    }
  }

  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) {
    if (column.isUnique!) {
      return [
        "CREATE UNIQUE INDEX ${dialect.uniqueKeyName(table.name ?? '', column.name)} "
        "ON ${table.name} (${_columnNameForColumn(column)})"
      ];
    } else {
      return [
        "DROP INDEX ${dialect.uniqueKeyName(table.name ?? '', column.name)} "
        "ON ${table.name}"
      ];
    }
  }

  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) {
    if (column.defaultValue != null) {
      return [
        "ALTER TABLE ${table.name} ALTER COLUMN "
        "${_columnNameForColumn(column)} SET DEFAULT ${column.defaultValue}"
      ];
    } else {
      return [
        "ALTER TABLE ${table.name} ALTER COLUMN "
        "${_columnNameForColumn(column)} DROP DEFAULT"
      ];
    }
  }

  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) {
    final allCommands = <String>[];
    allCommands.add(
      "ALTER TABLE ${table.name} DROP FOREIGN KEY "
      "${dialect.foreignKeyName(table.name ?? '', column.name)}",
    );
    allCommands.addAll(_addConstraintsForColumn(table.name, column));
    return allCommands;
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
    final existing = dialect.indexName(
      table.name ?? '',
      _columnNameForColumn(column),
    );
    return [
      "ALTER TABLE ${table.name} RENAME INDEX $existing TO $newIndexName"
    ];
  }

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    return [
      "DROP INDEX ${dialect.indexName(table.name ?? '', _columnNameForColumn(column))} "
      "ON ${table.name}"
    ];
  }

  // -- helpers --------------------------------------------------------------

  String _columnStringForColumn(SchemaColumn col) {
    final elements = [_columnNameForColumn(col), _columnTypeForColumn(col)];
    if (col.isPrimaryKey!) {
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

  List<String> _addConstraintsForColumn(
    String? tableName,
    SchemaColumn column,
  ) {
    var constraints =
        "ALTER TABLE $tableName "
        "ADD FOREIGN KEY (${_columnNameForColumn(column)}) "
        "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) ";

    if (column.deleteRule != null) {
      constraints +=
          "ON DELETE ${_deleteRuleStringForDeleteRule(SchemaColumn.deleteRuleStringForDeleteRule(column.deleteRule!))}";
    }

    return [constraints];
  }

  String? _deleteRuleStringForDeleteRule(String? deleteRule) {
    switch (deleteRule) {
      case "cascade":
        return "CASCADE";
      case "restrict":
        return "RESTRICT";
      case "default":
        return "SET DEFAULT";
      case "nullify":
        return "SET NULL";
    }
    return null;
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
