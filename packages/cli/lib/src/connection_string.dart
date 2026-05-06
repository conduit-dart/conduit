import 'package:conduit_core/conduit_core.dart';

/// Catalog of database flavors recognised by the `conduit db` CLI.
/// Each value names a dialect *family* — e.g. `postgres` covers both
/// `postgres://` and `postgresql://` URIs, and Cockroach speaks the
/// Postgres wire protocol so reuses the same enum entry. The CLI
/// never hard-codes which package implements a flavor; it just
/// lowers the parsed URI back into a flavor + DSN, and the
/// store-construction step is parameterised by flavor.
enum DbFlavor {
  postgres('postgres'),
  sqlite('sqlite'),
  mysql('mysql');

  const DbFlavor(this.canonical);

  /// Canonical scheme name (the form preferred in CLI help text).
  final String canonical;
}

/// Parsed connection string. Mirrors the shape of
/// `DatabaseConfiguration` but generalises over schemes the CLI
/// understands. The CLI converts this to a concrete `PersistentStore`
/// at the boundary where the per-backend package is imported (avoids
/// pulling sqlite/mysql packages into the CLI proper if the user
/// never invokes them).
class ParsedConnection {
  ParsedConnection({
    required this.flavor,
    required this.raw,
    this.username,
    this.password,
    this.host,
    this.port,
    this.databaseName,
    this.sqlitePath,
    this.sqliteInMemory = false,
  });

  /// The dialect family, or `null` if the URL didn't match any known
  /// scheme. `parseConnectionString` raises rather than returning a
  /// null flavor — this is non-null in practice but kept nullable to
  /// keep the data class straightforward to extend.
  final DbFlavor flavor;

  /// Original connection-string input — useful for diagnostics.
  final String raw;

  // Postgres / MySQL fields (nullable; unused for SQLite).
  final String? username;
  final String? password;
  final String? host;
  final int? port;
  final String? databaseName;

  // SQLite-specific.
  final String? sqlitePath;
  final bool sqliteInMemory;

  /// `true` when the parsed scheme uses a wire protocol (postgres/
  /// mysql) and thus needs a `host`/`port` to dial. Used by callers to
  /// decide whether to require the host fields.
  bool get isWire => flavor == DbFlavor.postgres || flavor == DbFlavor.mysql;
}

/// Connection-string-format error. Surfaces alongside `CLIException`
/// at the command boundary; raising a typed error here keeps the
/// pure-parsing module independent of the CLI's exception types.
class ConnectionStringFormatException implements Exception {
  ConnectionStringFormatException(this.message);
  final String message;

  @override
  String toString() => 'ConnectionStringFormatException: $message';
}

/// Parse a connection string. Recognised forms:
///
///   * `postgres://user:pass@host:port/db`     → [DbFlavor.postgres]
///   * `postgresql://...`                      → [DbFlavor.postgres]
///   * `sqlite::memory:`                       → [DbFlavor.sqlite] (in-memory)
///   * `sqlite:///absolute/path/to/file.db`    → [DbFlavor.sqlite]
///   * `sqlite://relative/path/file.db`        → [DbFlavor.sqlite]
///   * `mysql://user:pass@host:port/db`        → [DbFlavor.mysql]
///
/// CockroachDB speaks the Postgres wire protocol, so a Cockroach
/// connection string uses `postgres://...` and resolves to the
/// Postgres store. Callers that need to flag Cockroach for behavior
/// gating should consult the dialect annotations system instead of
/// trying to detect it from the URL.
ParsedConnection parseConnectionString(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw ConnectionStringFormatException(
        'Connection string is empty; expected e.g. '
        'postgres://user:pass@host:port/db or sqlite::memory:.');
  }

  // SQLite has two forms that don't survive a strict `Uri.parse` —
  // `sqlite::memory:` (path is itself `:memory:`) and `sqlite://`
  // with a *relative* path. Handle both as a string-prefix match
  // before dropping into Uri.parse for the URL-shaped ones.
  if (trimmed == 'sqlite::memory:') {
    return ParsedConnection(
      flavor: DbFlavor.sqlite,
      raw: trimmed,
      sqliteInMemory: true,
    );
  }
  if (trimmed.startsWith('sqlite://')) {
    final rest = trimmed.substring('sqlite://'.length);
    if (rest.isEmpty) {
      throw ConnectionStringFormatException(
          'sqlite:// requires a path: e.g. sqlite:///tmp/conduit.db, '
          'sqlite://relative/file.db, or sqlite::memory: for an in-memory '
          'database.');
    }
    return ParsedConnection(
      flavor: DbFlavor.sqlite,
      raw: trimmed,
      sqlitePath: rest,
    );
  }

  Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } on FormatException catch (e) {
    throw ConnectionStringFormatException(
        'Could not parse connection string "$trimmed": ${e.message}');
  }

  final scheme = uri.scheme.toLowerCase();
  switch (scheme) {
    case 'postgres':
    case 'postgresql':
      return _parseWire(uri, DbFlavor.postgres, trimmed);
    case 'mysql':
      return _parseWire(uri, DbFlavor.mysql, trimmed);
    case 'sqlite':
      // Already handled above. If we got here the input was
      // `sqlite:` without `//`, which we reject so users don't
      // mistakenly think `sqlite:relative` is supported.
      throw ConnectionStringFormatException(
          'sqlite connection strings must use sqlite:// (with two slashes) '
          'or the literal sqlite::memory:, got "$trimmed".');
    default:
      throw ConnectionStringFormatException(
          'Unsupported scheme "$scheme" — expected one of postgres, '
          'postgresql, sqlite, mysql.');
  }
}

ParsedConnection _parseWire(Uri uri, DbFlavor flavor, String raw) {
  if (uri.host.isEmpty) {
    throw ConnectionStringFormatException(
        '${flavor.canonical}:// requires a host, got "$raw".');
  }
  if (uri.pathSegments.isEmpty || uri.pathSegments.first.isEmpty) {
    throw ConnectionStringFormatException(
        '${flavor.canonical}:// requires a database name in the path, '
        'got "$raw".');
  }

  String? user;
  String? pass;
  if (uri.userInfo.isNotEmpty) {
    final parts = uri.userInfo.split(':');
    user = Uri.decodeComponent(parts.first);
    if (parts.length > 1) {
      pass = Uri.decodeComponent(parts.sublist(1).join(':'));
    }
  }

  final defaultPort =
      flavor == DbFlavor.postgres ? 5432 : 3306; // mysql default
  return ParsedConnection(
    flavor: flavor,
    raw: raw,
    username: user,
    password: pass,
    host: uri.host,
    port: uri.hasPort ? uri.port : defaultPort,
    databaseName: uri.pathSegments.first,
  );
}

/// Construct a [PersistentStore] for a parsed connection. The
/// per-backend store is loaded via the package import block at the
/// call site — this function takes typed factories so the CLI's core
/// logic doesn't need a hard dependency on every backend package.
///
/// The CLI passes only the postgres factory by default (since
/// `conduit_postgresql` is already a CLI dependency). When the user
/// invokes a sqlite/mysql connection string the CLI surfaces a clear
/// error pointing at the dev_dependencies the consumer needs to add
/// — see `database_connecting.dart` for the wiring.
PersistentStore? buildStore(
  ParsedConnection conn, {
  PersistentStore Function(ParsedConnection)? postgresFactory,
  PersistentStore Function(ParsedConnection)? sqliteFactory,
  PersistentStore Function(ParsedConnection)? mysqlFactory,
}) {
  switch (conn.flavor) {
    case DbFlavor.postgres:
      if (postgresFactory == null) return null;
      return postgresFactory(conn);
    case DbFlavor.sqlite:
      if (sqliteFactory == null) return null;
      return sqliteFactory(conn);
    case DbFlavor.mysql:
      if (mysqlFactory == null) return null;
      return mysqlFactory(conn);
  }
}
