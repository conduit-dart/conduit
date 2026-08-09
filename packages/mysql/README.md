# conduit_mysql

MySQL / MariaDB backend for the [Conduit](https://github.com/conduit-dart/conduit)
ORM: schema management + migrations, transactions, and a raw
`execute`/`executeQuery` path over `package:mysql_dart` (native Dart,
MySQL 5.7/8 and MariaDB 10/11).

## Install

```yaml
dependencies:
  conduit_mysql: ^7.0.0
```

## Use

```dart
import 'package:conduit_mysql/conduit_mysql.dart';

final store = MysqlPersistentStore(
  'user', 'password', '127.0.0.1', 3306, 'mydb',
);
```

Connection-string form: `mysql://user:password@host:3306/database`
(port defaults to 3306). Parameters are positional `?` placeholders.

## Status

Published from the Conduit 7.0.0 release; treat the public API as stable.
The ORM `newQuery<T>` path is not yet implemented for this backend — it is
blocked on extracting the query builders from `conduit_postgresql` into
core. Until then use schema management, migrations, and the raw execute
path. Known dialect gaps (no `RETURNING`, `JSON` vs `JSONB` operators,
collation-dependent case sensitivity) are documented in
[`doc/usage.md`](doc/usage.md).
