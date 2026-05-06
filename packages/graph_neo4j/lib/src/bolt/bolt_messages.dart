// Bolt v4.x message tags and constructors.
//
// Each request message is a PackStream Structure with a known tag and
// field count; this module wraps the construction so callers don't
// have to remember the tag bytes. The Bolt 4.4 spec is the reference:
// https://neo4j.com/docs/bolt/current/bolt/message/
//
// Subset implemented (per package scope — see ../bolt/README at the
// top of bolt_connection.dart):
//
//   request:  HELLO RUN PULL BEGIN COMMIT ROLLBACK RESET GOODBYE
//   summary:  SUCCESS FAILURE IGNORED
//   detail:   RECORD
//
// Not implemented: DISCARD, ROUTE, LOGON / LOGOFF (Bolt 5.1+), TELEMETRY.
library;

import 'packstream.dart';

/// Bolt message tag constants.
abstract final class BoltTag {
  // Requests.
  static const int hello = 0x01;
  static const int goodbye = 0x02;
  static const int reset = 0x0F;
  static const int run = 0x10;
  static const int begin = 0x11;
  static const int commit = 0x12;
  static const int rollback = 0x13;
  static const int discard = 0x2F;
  static const int pull = 0x3F;

  // Summary / detail.
  static const int success = 0x70;
  static const int record = 0x71;
  static const int ignored = 0x7E;
  static const int failure = 0x7F;
}

/// Construct a HELLO request.
///
/// `extra` carries the `user_agent` plus auth fields (`scheme`,
/// `principal`, `credentials`).
BoltStructure helloMessage({
  required String userAgent,
  String? scheme,
  String? principal,
  String? credentials,
  Map<String, Object?> extra = const {},
}) {
  final body = <String, Object?>{
    'user_agent': userAgent,
    ...extra,
  };
  if (scheme != null) {
    body['scheme'] = scheme;
    if (principal != null) body['principal'] = principal;
    if (credentials != null) body['credentials'] = credentials;
  } else {
    // Anonymous / no-auth.
    body['scheme'] = 'none';
  }
  return BoltStructure(BoltTag.hello, [body]);
}

/// Construct a GOODBYE request (no fields).
BoltStructure goodbyeMessage() => BoltStructure(BoltTag.goodbye, const []);

/// Construct a RESET request (no fields).
BoltStructure resetMessage() => BoltStructure(BoltTag.reset, const []);

/// Construct a RUN request.
///
/// `extra` typically carries `db` (target database) and `mode` (`r` for
/// read-only). Empty by default.
BoltStructure runMessage({
  required String cypher,
  Map<String, Object?> parameters = const {},
  Map<String, Object?> extra = const {},
}) =>
    BoltStructure(BoltTag.run, [cypher, parameters, extra]);

/// Construct a PULL request.
///
/// `n` defaults to -1 ("pull all remaining records"). `qid` is the
/// query id when streaming multiple statements; -1 for "the most
/// recent query".
BoltStructure pullMessage({int n = -1, int qid = -1}) =>
    BoltStructure(BoltTag.pull, [
      <String, Object?>{'n': n, 'qid': qid},
    ]);

/// Construct a BEGIN request.
BoltStructure beginMessage({Map<String, Object?> extra = const {}}) =>
    BoltStructure(BoltTag.begin, [extra]);

/// Construct a COMMIT request (no fields).
BoltStructure commitMessage() => BoltStructure(BoltTag.commit, const []);

/// Construct a ROLLBACK request (no fields).
BoltStructure rollbackMessage() => BoltStructure(BoltTag.rollback, const []);
