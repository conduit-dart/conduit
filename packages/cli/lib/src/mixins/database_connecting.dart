import 'dart:async';
import 'dart:io';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/connection_string.dart';
import 'package:conduit/src/metadata.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_postgresql/conduit_postgresql.dart';

mixin CLIDatabaseConnectingCommand implements CLICommand, CLIProject {
  static const String flavorPostgreSQL = "postgres";
  static const String flavorSQLite = "sqlite";
  static const String flavorMySQL = "mysql";

  late DatabaseConfiguration connectedDatabase;

  @Flag(
    "use-ssl",
    help: "DEPRECATED: Use ssl-mode instead",
    defaultsTo: false,
  )
  bool get useSSL => decode("use-ssl");

  @Option("ssl-mode",
      help:
          "Whether or not the database connection should use SSL (disable/require/verifyFull)",
      defaultsTo: "disable")
  String get sslMode => decode("ssl-mode");

  @Option(
    "connect",
    abbr: "c",
    help:
        "A database connection URI string. If this option is set, database-config is ignored.",
    valueHelp: "postgres://user:password@localhost:port/databaseName",
  )
  String? get databaseConnectionString => decodeOptional("connect");

  /// Multi-backend alias of `--connect`. Accepts URIs whose scheme
  /// names the backend: `postgres://`, `postgresql://`, `sqlite://`,
  /// `sqlite::memory:`, `mysql://`. When both are set, `--connection`
  /// wins — its richer scheme dispatch is the migration path.
  @Option(
    "connection",
    help:
        "Multi-backend connection URI. Scheme dispatches the backend "
        "(postgres://, postgresql://, sqlite://, sqlite::memory:, mysql://).",
    valueHelp: "scheme://[user:pass@]host[:port]/db",
  )
  String? get multiBackendConnectionString => decodeOptional("connection");

  @Option(
    "flavor",
    abbr: "f",
    help: "The database driver flavor to use.",
    defaultsTo: "postgres",
    allowed: ["postgres", "sqlite", "mysql"],
  )
  String get databaseFlavor => decode("flavor");

  @Option(
    "database-config",
    help:
        "A configuration file that provides connection information for the database. "
        "Paths are relative to project directory. If the connect option is set, this value is ignored. "
        "See 'conduit db -h' for details.",
    defaultsTo: "database.yaml",
  )
  File get databaseConfigurationFile =>
      fileInProjectDirectory(decode("database-config"));

  PersistentStore? _persistentStore;

  PersistentStore get persistentStore {
    if (_persistentStore != null) {
      return _persistentStore!;
    }

    // The new `--connection` flag is the multi-backend entrypoint.
    // It takes precedence over the legacy `--connect` + `--flavor`
    // combination because its scheme is unambiguous about the
    // backend.
    if (multiBackendConnectionString != null) {
      _persistentStore = _buildFromMultiBackend(multiBackendConnectionString!);
      return _persistentStore!;
    }

    if (databaseFlavor == flavorPostgreSQL) {
      if (databaseConnectionString != null) {
        try {
          connectedDatabase = DatabaseConfiguration();
          connectedDatabase.decode(databaseConnectionString);
        } catch (_) {
          throw CLIException(
            "Invalid database configuration.",
            instructions: [
              "Invalid connection string was: $databaseConnectionString",
              "Expected format:               database://user:password@host:port/databaseName"
            ],
          );
        }
      } else {
        if (!databaseConfigurationFile.existsSync()) {
          throw CLIException(
            "No database configuration file found.",
            instructions: [
              "Expected file at: ${databaseConfigurationFile.path}.",
              "See --connect and --database-config. If not using --connect, "
                  "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
            ],
          );
        }

        try {
          connectedDatabase =
              DatabaseConfiguration.fromFile(databaseConfigurationFile);
        } catch (_) {
          throw CLIException(
            "Invalid database configuration.",
            instructions: [
              "File located at ${databaseConfigurationFile.path}.",
              "See --connect and --database-config. If not using --connect, "
                  "this tool expects a YAML configuration file with the following format:\n$_dbConfigFormat"
            ],
          );
        }
      }

      return _persistentStore = PostgreSQLPersistentStore(
        connectedDatabase.username,
        connectedDatabase.password,
        connectedDatabase.host,
        connectedDatabase.port,
        connectedDatabase.databaseName,
        sslMode: sslMode,
      );
    }

    throw CLIException(
      "Invalid flavor $databaseFlavor",
      instructions: const [
        "Use --connection scheme://… instead of --flavor when targetting "
            "non-postgres backends; the scheme picks the dialect.",
      ],
    );
  }

  /// Build a [PersistentStore] (and populate [connectedDatabase] for
  /// the wire-protocol cases) from the new `--connection` flag.
  PersistentStore _buildFromMultiBackend(String raw) {
    ParsedConnection conn;
    try {
      conn = parseConnectionString(raw);
    } on ConnectionStringFormatException catch (e) {
      throw CLIException(
        "Invalid --connection URI.",
        instructions: [
          e.message,
          'Examples:',
          '  postgres://user:pass@host:5432/db',
          '  sqlite::memory:',
          '  sqlite:///tmp/conduit.db',
          '  mysql://user:pass@host:3306/db',
        ],
      );
    }

    switch (conn.flavor) {
      case DbFlavor.postgres:
        connectedDatabase = DatabaseConfiguration.withConnectionInfo(
          conn.username,
          conn.password,
          conn.host!,
          conn.port!,
          conn.databaseName!,
        );
        return PostgreSQLPersistentStore(
          conn.username,
          conn.password,
          conn.host,
          conn.port,
          conn.databaseName,
          sslMode: sslMode,
        );
      case DbFlavor.sqlite:
        // SQLite is opt-in: the consumer must add `conduit_sqlite` to
        // their dev_dependencies and use `--connection` from a project
        // that imports it. We can't import `conduit_sqlite` here
        // without making the CLI itself depend on it, so we surface a
        // clear error path.
        throw CLIException(
          'SQLite is not yet wired into the bundled `conduit` CLI binary.',
          instructions: const [
            'The `--connection sqlite://...` URI is *parsed* and dispatched '
                'correctly, but constructing a SqlitePersistentStore from '
                'inside the CLI requires the CLI to depend on '
                '`conduit_sqlite` — which we have deferred to keep the CLI '
                'install footprint small.',
            'For now: add `conduit_sqlite` to your project\'s '
                'dev_dependencies and use `dart run conduit:db_upgrade` from '
                'inside the project, where the runtime can resolve sqlite '
                'against the project\'s package config.',
            'Tracking: this is the same wiring deferred for ORM newQuery<T> '
                'support; both ride on the SqlExpression AST migration.',
          ],
        );
      case DbFlavor.mysql:
        // Same wiring story as SQLite: emit a warning + clear path.
        throw CLIException(
          'MySQL is not yet wired into the bundled `conduit` CLI binary.',
          instructions: const [
            'The `--connection mysql://...` URI is *parsed* and dispatched '
                'correctly, but the ORM path for MySQL is not yet '
                'implemented (raw execute + schema-only). Use raw SQL or '
                'the schema-builder API directly until newQuery<T> lands.',
            'For now: add `conduit_mysql` to your project\'s '
                'dev_dependencies and use the harness in your test code '
                'directly.',
          ],
        );
    }
  }

  @override
  Future? cleanup() async {
    return _persistentStore?.close();
  }

  String get _dbConfigFormat {
    return "\n\tusername: username\n\tpassword: password\n\thost: host\n\tport: port\n\tdatabaseName: name\n";
  }
}
