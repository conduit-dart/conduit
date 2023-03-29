import 'package:conduit_core/conduit_core.dart';

class MySqlSchemaGenerator {
  String get versionTableName => "_conduit_version_mysql";

  List<String> createTable(SchemaTable table, {bool isTemporary = false}) {
    final commands = <String>[];

    // Create table command
    final columnString = table.columns.map(_columnStringForColumn).join(",");
    commands.add(
      "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} ($columnString)",
    );

    final indexCommands = table.columns
        .where(
          (col) => col.isIndexed! && !col.isPrimaryKey!,
        ) // primary keys are auto-indexed
        .map((col) => addIndexToColumn(table, col))
        .expand((commands) => commands);
    commands.addAll(indexCommands);

    commands.addAll(
      table.columns
          .where((sc) => sc.isForeignKey)
          .map((col) => _addConstraintsForColumn(table.name, col))
          .expand((commands) => [commands]),
    );

    if (table.uniqueColumnSet != null) {
      commands.addAll(addTableUniqueColumnSet(table));
    }

    return commands;
  }

  List<String> renameTable(SchemaTable table, String name) {
    // Must rename indices, constraints, etc.
    throw UnsupportedError("renameTable is not yet supported.");
  }

  List<String> deleteTable(SchemaTable table) {
    return ["DROP TABLE ${table.name}"];
  }

  List<String> addTableUniqueColumnSet(SchemaTable table) {
    final colNames = table.uniqueColumnSet!.map((name) {
      if (table[name]?.typeString! == 'string') {
        return '${_columnNameForColumn(table[name]!)}(${table[name]!.keyLength})';
      }
      return _columnNameForColumn(table[name]!);
    }).join(",");
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
      commands.addAll([
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}",
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} DROP DEFAULT"
      ]);
    } else {
      commands.addAll([
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}"
      ]);
    }

    if (column.isIndexed!) {
      commands.addAll(addIndexToColumn(table, column));
    }

    if (column.isForeignKey) {
      commands.add(_addConstraintsForColumn(table.name, column));
    }

    return commands;
  }

  List<String> deleteColumn(SchemaTable table, SchemaColumn column) {
    return [
      "ALTER TABLE ${table.name} ${column.isForeignKey ? 'DROP FOREIGN KEY ${_foreignKeyName(column.relatedTableName, column)}, ' : ''}DROP COLUMN ${_columnNameForColumn(column)} ${column.relatedColumnName != null ? "CASCADE" : "RESTRICT"}"
    ];
  }

  List<String> renameColumn(
    SchemaTable table,
    SchemaColumn column,
    String name,
  ) {
    // Must rename indices, constraints, etc.
    throw UnsupportedError("renameColumn is not yet supported.");
  }

  List<String> alterColumnNullability(
    SchemaTable table,
    SchemaColumn column,
    String? unencodedInitialValue,
  ) {
    if (column.isNullable!) {
      return [
        "ALTER TABLE ${table.name} MODIFY COLUMN ${_columnNameForColumn(column)} ${_mySQLTypeForColumn(column)} NULL"
      ];
    } else {
      if (unencodedInitialValue != null) {
        return [
          "UPDATE ${table.name} SET ${_columnNameForColumn(column)}=$unencodedInitialValue WHERE ${_columnNameForColumn(column)} IS NULL",
          "ALTER TABLE ${table.name} MODIFY COLUMN ${_columnNameForColumn(column)} ${_mySQLTypeForColumn(column)} NOT NULL",
        ];
      } else {
        return [
          "ALTER TABLE ${table.name} MODIFY COLUMN ${_columnNameForColumn(column)} ${_mySQLTypeForColumn(column)} NOT NULL"
        ];
      }
    }
  }

  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) {
    if (column.isUnique!) {
      return [
        "ALTER TABLE ${table.name} ADD CONSTRAINT ${_uniqueKeyName(table.name, column)} UNIQUE (${column.name})"
      ];
    } else {
      return [
        "ALTER TABLE ${table.name} DROP CONSTRAINT ${_uniqueKeyName(table.name, column)}"
      ];
    }
  }

  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) {
    if (column.defaultValue != null) {
      return [
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} SET DEFAULT ${column.defaultValue}"
      ];
    } else {
      return [
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} DROP DEFAULT"
      ];
    }
  }

  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) {
    final allCommands = <String>[];
    allCommands.add(
      "ALTER TABLE ${table.name} DROP CONSTRAINT ${_foreignKeyName(column.relatedTableName, column)}",
    );
    allCommands.add(_addConstraintsForColumn(table.name, column));
    return allCommands;
  }

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) {
    return [
      "CREATE INDEX ${_indexNameForColumn(table.name, column)} ON ${table.name} (${_columnNameForColumn(column)})"
    ];
  }

  List<String> renameIndex(
    SchemaTable table,
    SchemaColumn column,
    String newIndexName,
  ) {
    final existingIndexName = _indexNameForColumn(table.name, column);
    return ["ALTER INDEX $existingIndexName RENAME TO $newIndexName"];
  }

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    return [
      "DROP INDEX ${_indexNameForColumn(table.name, column)} ON ${table.name}"
    ];
  }

  ////

  String _uniqueKeyName(String? tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_key";
  }

  String _foreignKeyName(String? tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_fkey";
  }

  String _addConstraintsForColumn(
    String? tableName,
    SchemaColumn column,
  ) {
    var constraints =
        "ALTER TABLE $tableName ADD CONSTRAINT ${_foreignKeyName(column.relatedTableName, column)} FOREIGN KEY (${_columnNameForColumn(column)}) "
        "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) ";

    if (column.deleteRule != null) {
      constraints +=
          "ON DELETE ${_deleteRuleStringForDeleteRule(SchemaColumn.deleteRuleStringForDeleteRule(column.deleteRule!))}";
    }

    return constraints;
  }

  String _indexNameForColumn(String? tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_idx";
  }

  String _columnStringForColumn(SchemaColumn col) {
    final elements = [_columnNameForColumn(col), _mySQLTypeForColumn(col)];
    if (col.isPrimaryKey!) {
      elements.add("PRIMARY KEY");
    } else {
      elements.add(col.isNullable! ? "NULL" : "NOT NULL");
      if (col.defaultValue != null) {
        elements.add("DEFAULT ${col.defaultValue}");
      }
      if (col.isUnique!) {
        if (col.keyLength > 0) {
          elements.add(",UNIQUE");
          elements.add("(${_columnNameForColumn(col)}(${col.keyLength}))");
        } else {
          elements.add("UNIQUE");
        }
      }
    }

    return elements.join(" ");
  }

  String? _columnNameForColumn(SchemaColumn column) {
    if (column.relatedColumnName != null) {
      return "${column.name}_${column.relatedColumnName}";
    }

    return column.name;
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

  String? _mySQLTypeForColumn(SchemaColumn t) {
    switch (t.typeString) {
      case "integer":
        {
          if (t.autoincrement!) {
            return "INT NOT NULL AUTO_INCREMENT UNIQUE";
          }
          return "INT";
        }
      case "unsigned":
        return "INT UNSIGNED";
      case "bigUnsigned":
        {
          if (t.autoincrement!) {
            return "SERIAL";
          }
          return "BIGINT UNSIGNED";
        }
      case "bigInteger":
        return "BIGINT";
      case "string":
        return "TEXT(${t.keyLength})";
      case "datetime":
        return "DATETIME";
      case "boolean":
        return "BOOLEAN";
      case "double":
        return "DOUBLE";
      case "document":
        return "JSON";
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
