import 'package:conduit_sql/conduit_sql.dart';
import 'package:test/test.dart';

/// Tiny stub dialect used only to verify the abstract surface
/// compiles and behaves as documented. The real dialects (Postgres,
/// MySQL) land in subsequent phases.
class _StubDialect extends Dialect {
  const _StubDialect();

  @override
  String get name => 'stub';

  @override
  String quoteIdentifier(String identifier) => '"$identifier"';

  @override
  String parameterReference(int index, {String? name}) => '@p$index';

  @override
  String autoIncrementColumnType() => 'BIGSERIAL';

  @override
  String? columnTypeFor(String propertyType) => switch (propertyType) {
        'integer' => 'INTEGER',
        'string' => 'TEXT',
        _ => null,
      };

  @override
  String booleanLiteral(bool value) => value ? 'TRUE' : 'FALSE';

  @override
  DialectCapabilities get capabilities => const DialectCapabilities(
        supportsReturning: true,
        supportsJsonColumn: true,
      );
}

void main() {
  const dialect = _StubDialect();

  test('Dialect surface is implementable', () {
    expect(dialect.name, 'stub');
    expect(dialect.quoteIdentifier('foo'), '"foo"');
    expect(dialect.parameterReference(1), '@p1');
    expect(dialect.autoIncrementColumnType(), 'BIGSERIAL');
    expect(dialect.columnTypeFor('integer'), 'INTEGER');
    expect(dialect.columnTypeFor('unknown'), isNull);
    expect(dialect.booleanLiteral(true), 'TRUE');
    expect(dialect.booleanLiteral(false), 'FALSE');
  });

  test('DialectCapabilities default to most-portable values', () {
    const c = DialectCapabilities();
    expect(c.supportsReturning, isFalse);
    expect(c.supportsUpsert, isFalse);
    expect(c.supportsJsonColumn, isFalse);
    expect(c.supportsCheckConstraints, isFalse);
    expect(c.maxIdentifierLength, 63);
  });

  test('DialectCapabilities propagate overrides', () {
    expect(dialect.capabilities.supportsReturning, isTrue);
    expect(dialect.capabilities.supportsJsonColumn, isTrue);
    expect(dialect.capabilities.supportsUpsert, isFalse);
  });
}
