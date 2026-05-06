import 'package:conduit/src/connection_string.dart';
import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseConnectionString — postgres', () {
    test('parses postgres://user:pass@host:port/db', () {
      final c = parseConnectionString(
          'postgres://alice:secret@db.example.com:5432/myapp');
      expect(c.flavor, DbFlavor.postgres);
      expect(c.username, 'alice');
      expect(c.password, 'secret');
      expect(c.host, 'db.example.com');
      expect(c.port, 5432);
      expect(c.databaseName, 'myapp');
      expect(c.isWire, isTrue);
    });

    test('postgresql:// is an alias for postgres://', () {
      final c = parseConnectionString(
          'postgresql://alice:secret@db.example.com/myapp');
      expect(c.flavor, DbFlavor.postgres);
      expect(c.port, 5432, reason: 'default postgres port');
    });

    test('URL-decodes percent-encoded password', () {
      final c =
          parseConnectionString('postgres://alice:p%40ss@host:5432/db');
      expect(c.password, 'p@ss');
    });

    test('rejects missing host', () {
      expect(
        () => parseConnectionString('postgres:///mydb'),
        throwsA(isA<ConnectionStringFormatException>()),
      );
    });

    test('rejects missing database name', () {
      expect(
        () => parseConnectionString('postgres://alice@host:5432/'),
        throwsA(isA<ConnectionStringFormatException>()),
      );
    });
  });

  group('parseConnectionString — sqlite', () {
    test('sqlite::memory: is parsed as in-memory', () {
      final c = parseConnectionString('sqlite::memory:');
      expect(c.flavor, DbFlavor.sqlite);
      expect(c.sqliteInMemory, isTrue);
      expect(c.sqlitePath, isNull);
      expect(c.isWire, isFalse);
    });

    test('sqlite:///absolute/path/file.db parses as file path', () {
      final c = parseConnectionString('sqlite:///tmp/conduit.db');
      expect(c.flavor, DbFlavor.sqlite);
      expect(c.sqliteInMemory, isFalse);
      expect(c.sqlitePath, '/tmp/conduit.db');
    });

    test('sqlite://relative/path/file.db parses as relative path', () {
      final c = parseConnectionString('sqlite://relative/conduit.db');
      expect(c.flavor, DbFlavor.sqlite);
      expect(c.sqlitePath, 'relative/conduit.db');
    });

    test('rejects sqlite:// with empty path', () {
      expect(
        () => parseConnectionString('sqlite://'),
        throwsA(isA<ConnectionStringFormatException>()),
      );
    });

    test('rejects sqlite:relative (single slash)', () {
      expect(
        () => parseConnectionString('sqlite:relative.db'),
        throwsA(isA<ConnectionStringFormatException>()),
      );
    });
  });

  group('parseConnectionString — mysql', () {
    test('parses mysql://user:pass@host:port/db', () {
      final c = parseConnectionString(
          'mysql://root:hunter2@127.0.0.1:3306/widgets');
      expect(c.flavor, DbFlavor.mysql);
      expect(c.username, 'root');
      expect(c.password, 'hunter2');
      expect(c.host, '127.0.0.1');
      expect(c.port, 3306);
      expect(c.databaseName, 'widgets');
    });

    test('defaults port to 3306 when missing', () {
      final c =
          parseConnectionString('mysql://root:hunter2@127.0.0.1/widgets');
      expect(c.port, 3306);
    });
  });

  group('parseConnectionString — error paths', () {
    test('rejects empty input', () {
      expect(() => parseConnectionString(''),
          throwsA(isA<ConnectionStringFormatException>()));
      expect(() => parseConnectionString('   '),
          throwsA(isA<ConnectionStringFormatException>()));
    });

    test('rejects unknown scheme', () {
      expect(
        () => parseConnectionString('oracle://host:1521/orcl'),
        throwsA(predicate<ConnectionStringFormatException>(
            (e) => e.message.contains('Unsupported scheme'))),
      );
    });

    test('rejects garbage input', () {
      expect(
        () => parseConnectionString('not-a-uri-at-all'),
        throwsA(isA<ConnectionStringFormatException>()),
      );
    });
  });

  group('buildStore', () {
    test('returns null when factory is missing for the flavor', () {
      final c = parseConnectionString('postgres://u:p@h:5432/d');
      expect(buildStore(c), isNull);
    });

    test('invokes the postgres factory', () {
      final c = parseConnectionString('postgres://u:p@h:5432/d');
      var called = false;
      buildStore(c, postgresFactory: (_) {
        called = true;
        // Returning a real store is heavy; verify dispatch by side
        // effect rather than constructing a PostgreSQLPersistentStore
        // (which would try to open a connection).
        return _NoopStore();
      });
      expect(called, isTrue);
    });

    test('does not invoke postgres factory for sqlite URI', () {
      final c = parseConnectionString('sqlite::memory:');
      var pgCalled = false;
      var sqCalled = false;
      buildStore(
        c,
        postgresFactory: (_) {
          pgCalled = true;
          return _NoopStore();
        },
        sqliteFactory: (_) {
          sqCalled = true;
          return _NoopStore();
        },
      );
      expect(pgCalled, isFalse);
      expect(sqCalled, isTrue);
    });
  });
}

class _NoopStore implements PersistentStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
