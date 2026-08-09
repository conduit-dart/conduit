## 7.0.0

> Note: First publish to pub.dev. Requires Dart SDK >=3.12.0.

 - **FEAT**: add conduit_sqlite backend (schema + raw execute; ORM path deferred) ([#264](https://github.com/conduit-dart/conduit/pull/264)).
 - **FEAT**: multi-backend test harness + connection-string dispatch ([#268](https://github.com/conduit-dart/conduit/pull/268)).
 - **REFACTOR**: lift query builders to dialect-agnostic core; wire SQLite + MySQL newQuery ([#275](https://github.com/conduit-dart/conduit/pull/275)).
 - **FEAT**: `Document` (JSON-as-TEXT) column support — JSON-encode on write / decode on read via the new `SqlDialect.decodeValue` seam (Postgres `jsonb` path unchanged).
 - **TEST**: cover `hasMany` `ManagedSet` eager-fetch (`join(set:)`) and `Document` round-trips; reconcile the README / usage docs / docstrings to reflect the now-complete `newQuery<T>` ORM surface.
