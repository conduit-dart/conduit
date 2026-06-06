# Migration Notes

* [4.1.8.md]
* [4.3.6.md]
* [6.0.md] — `ServiceRegistry` removed, snake_case naming (opt-in),
  `PostgresTestConfig` defaults, Dart `>=3.11.0`, `conduit_common_test`
  retired.
* [7.0.md] — `conduit build` retired, `build_runner` + `dart compile exe`
  is the new AOT path; first publish of `conduit_sqlite`, `_mysql`,
  `_graph`, `_graph_neo4j`, `_graphql`; unified `PersistenceContext`;
  dialect-agnostic `newQuery<T>`; Dart `>=3.12.0`.
