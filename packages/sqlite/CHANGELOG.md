## 7.0.0

> Note: First publish to pub.dev. Requires Dart SDK >=3.12.0.

 - **FEAT**: add conduit_sqlite backend (schema + raw execute; ORM path deferred) ([#264](https://github.com/conduit-dart/conduit/pull/264)).
 - **FEAT**: multi-backend test harness + connection-string dispatch ([#268](https://github.com/conduit-dart/conduit/pull/268)).
 - **REFACTOR**: lift query builders to dialect-agnostic core; wire SQLite + MySQL newQuery ([#275](https://github.com/conduit-dart/conduit/pull/275)).
