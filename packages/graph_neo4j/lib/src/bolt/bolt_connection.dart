// Minimal Bolt v4.x client over a raw `dart:io` Socket.
//
// Scope and non-goals
// -------------------
// This is a deliberately small client targeted at backing
// `Neo4jPersistentStore`. It implements:
//
//   - TCP connect (Bolt is binary-over-TCP; **not** WebSocket)
//   - Bolt handshake: `60 60 B0 17` magic + four version offers,
//     server picks one
//   - Chunked message framing (2-byte big-endian size header + body,
//     terminated by an empty `00 00` chunk)
//   - HELLO with optional basic-auth, autocommit RUN/PULL pairs, and
//     explicit BEGIN / COMMIT / ROLLBACK transaction control
//   - GOODBYE + close
//
// What we deliberately do NOT implement (call out at the top so a
// reader does not go looking):
//
//   - clustering / routing (`neo4j://` scheme, ROUTE messages)
//   - bookmarks or causal consistency beyond what a single connection
//     gives you
//   - streaming pipelines / multiple in-flight RUNs (we serialize
//     RUN+PULL pairs)
//   - Bolt 5+ specific messages (LOGON / LOGOFF / TELEMETRY)
//   - DISCARD (callers always PULL)
//   - TLS handshake — the `bolt://` scheme implies plaintext; if you
//     need encryption today, terminate it at a sidecar / SSH tunnel.
//     `bolt+s://` is on the roadmap, not v0.
//
// All of the above are documented as future work in the package README.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'bolt_messages.dart';
import 'packstream.dart';

/// Raised by the Bolt client when the wire-level protocol fails.
class BoltProtocolException implements Exception {
  BoltProtocolException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() {
    final c = cause == null ? '' : ' (cause: $cause)';
    return 'BoltProtocolException: $message$c';
  }
}

/// Raised when the server responds with a FAILURE message.
///
/// Carries the server-supplied `code` (e.g.
/// `Neo.ClientError.Statement.SyntaxError`) and `message`.
class BoltFailure implements Exception {
  BoltFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'BoltFailure($code): $message';
}

/// One row of a query result. The row is positional; pair it with
/// `BoltResult.fields` for the column names.
class BoltRecord {
  BoltRecord(List<Object?> values) : values = List.unmodifiable(values);
  final List<Object?> values;

  /// Convenience: zip the row against a column-name list into a map.
  Map<String, Object?> asMap(List<String> fields) {
    final m = <String, Object?>{};
    for (var i = 0; i < fields.length && i < values.length; i++) {
      m[fields[i]] = values[i];
    }
    return m;
  }

  @override
  String toString() => 'BoltRecord($values)';
}

/// The full result of a RUN+PULL pair: the column names announced by
/// the RUN SUCCESS, the records returned by PULL, and the trailing
/// SUCCESS metadata.
class BoltResult {
  BoltResult({
    required this.fields,
    required this.records,
    required this.summary,
  });

  final List<String> fields;
  final List<BoltRecord> records;
  final Map<String, Object?> summary;

  /// Hydrate every row into a `Map<String, Object?>` using [fields].
  List<Map<String, Object?>> rowsAsMaps() =>
      records.map((r) => r.asMap(fields)).toList(growable: false);
}

/// The Bolt protocol version a connection negotiated.
class BoltVersion {
  const BoltVersion(this.major, this.minor);
  final int major;
  final int minor;
  bool get isUnsupported => major == 0 && minor == 0;
  int get encoded => ((minor & 0xFF) << 8) | (major & 0xFF);
  @override
  String toString() => 'Bolt $major.$minor';
}

/// Versions we offer in the handshake, in preference order.
///
/// 4.4 / 4.3 / 4.1 / 4.0 covers every Neo4j 4.x server, and Neo4j 5.x
/// servers fall back to negotiating 4.4. We do not offer 5.x — that
/// adds a LOGON/LOGOFF auth dance that is out of scope here.
const List<BoltVersion> _offeredVersions = [
  BoltVersion(4, 4),
  BoltVersion(4, 3),
  BoltVersion(4, 1),
  BoltVersion(4, 0),
];

/// The Bolt magic preamble.
const List<int> _boltMagic = [0x60, 0x60, 0xB0, 0x17];

/// Maximum chunk body size (Bolt uses a 16-bit unsigned size header).
const int _maxChunkBody = 0xFFFF;

/// Reads chunked Bolt frames off a stream and reassembles them into
/// full message bodies. Multiple chunks form one message; an empty
/// `00 00` chunk terminates the message.
class _ChunkReassembler {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final BytesBuilder _currentMessage = BytesBuilder(copy: false);

  /// Pending chunk-body bytes still to consume from the current chunk
  /// (-1 means "I haven't read the size header yet").
  int _expecting = -1;

  /// Reassembled messages awaiting `pop()`.
  final List<Uint8List> _messages = [];

  /// Feed raw socket bytes into the reassembler.
  void feed(List<int> data) {
    _buffer.add(data);
    _drain();
  }

  /// Pop one fully-reassembled message body, or `null` if none ready.
  Uint8List? pop() {
    if (_messages.isEmpty) return null;
    return _messages.removeAt(0);
  }

  void _drain() {
    while (true) {
      final buf = _buffer.toBytes();
      if (_expecting == -1) {
        // Need a 2-byte chunk header.
        if (buf.length < 2) {
          _resetBufferTo(buf, 0);
          return;
        }
        final size = (buf[0] << 8) | buf[1];
        _resetBufferTo(buf, 2);
        if (size == 0) {
          // End-of-message marker.
          _messages.add(_currentMessage.takeBytes());
          // Reset for next message.
          continue;
        }
        _expecting = size;
      } else {
        final buf2 = _buffer.toBytes();
        if (buf2.isEmpty) return;
        final take = buf2.length < _expecting ? buf2.length : _expecting;
        _currentMessage.add(buf2.sublist(0, take));
        _resetBufferTo(buf2, take);
        _expecting -= take;
        if (_expecting == 0) {
          _expecting = -1;
        }
      }
    }
  }

  void _resetBufferTo(Uint8List current, int offset) {
    _buffer.clear();
    if (offset < current.length) {
      _buffer.add(current.sublist(offset));
    }
  }
}

/// A single Bolt connection.
///
/// Not safe for concurrent use — calls must be serialized by the
/// caller (`Neo4jPersistentStore` does this with a per-call lock).
class BoltConnection {
  BoltConnection._(this._socket, this.version);

  final Socket _socket;

  /// Negotiated Bolt protocol version.
  final BoltVersion version;

  final _ChunkReassembler _reassembler = _ChunkReassembler();
  // Pending response bodies, oldest first. Used when the server emits
  // a message before the consumer has a waiter ready (common for the
  // RECORD+SUCCESS sequence after a single PULL).
  final List<Uint8List> _pendingResponses = [];
  // Consumers waiting for a response when none is buffered.
  final List<Completer<Uint8List>> _waiters = [];
  StreamSubscription<List<int>>? _subscription;
  bool _closed = false;
  Object? _socketError;

  /// Connect to [host]:[port], perform the Bolt handshake, and return
  /// the resulting connection (still un-authenticated — call [hello]).
  static Future<BoltConnection> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);

    // Send magic + four version offers.
    final hs = BytesBuilder(copy: false)
      ..add(_boltMagic);
    for (final v in _offeredVersions) {
      // Each offer is a 32-bit big-endian word: 00 00 minor major.
      hs
        ..addByte(0)
        ..addByte(0)
        ..addByte(v.minor & 0xFF)
        ..addByte(v.major & 0xFF);
    }
    socket.add(hs.takeBytes());
    await socket.flush();

    // Read the 4-byte server response (its chosen version).
    final respBytes = await _readExactly(socket, 4);
    final chosen = BoltVersion(respBytes[3], respBytes[2]);
    if (chosen.isUnsupported) {
      await socket.close();
      throw BoltProtocolException(
        'server rejected the handshake (no supported Bolt version found '
        'in our offer ${_offeredVersions.join(", ")})',
      );
    }
    if (chosen.major != 4) {
      await socket.close();
      throw BoltProtocolException(
        'server selected unsupported Bolt $chosen — this client only '
        'speaks Bolt 4.x',
      );
    }
    final conn = BoltConnection._(socket, chosen);
    conn._startReader();
    return conn;
  }

  /// Send HELLO with the given user agent and credentials.
  ///
  /// Pass `null` for [username] / [password] to attempt anonymous auth.
  Future<Map<String, Object?>> hello({
    String userAgent = 'conduit_graph_neo4j/0.1',
    String? username,
    String? password,
  }) async {
    final msg = helloMessage(
      userAgent: userAgent,
      scheme: username == null ? null : 'basic',
      principal: username,
      credentials: password,
    );
    final reply = await _exchange(msg);
    return _expectSuccess(reply, 'HELLO');
  }

  /// Run a single statement in autocommit mode and pull all rows.
  ///
  /// Returns a [BoltResult] with column names + records. Throws
  /// [BoltFailure] on a server-side error.
  Future<BoltResult> runAndPull(
    String cypher, {
    Map<String, Object?> parameters = const {},
    Map<String, Object?> extra = const {},
  }) async {
    final runReply = await _exchange(
      runMessage(cypher: cypher, parameters: parameters, extra: extra),
    );
    final runMeta = _expectSuccess(runReply, 'RUN');
    final fields = (runMeta['fields'] as List?)?.cast<String>() ?? <String>[];

    // PULL emits 0..N RECORDs followed by a SUCCESS (or FAILURE /
    // IGNORED). `_exchange` returns a single response — we send
    // PULL once and then read additional responses until we hit a
    // summary message.
    final records = <BoltRecord>[];
    var first = await _exchange(pullMessage());
    Map<String, Object?>? pullSummary;
    while (true) {
      final s = first;
      if (s.tag == BoltTag.failure) {
        _throwFailure(s);
      }
      if (s.tag == BoltTag.ignored) {
        throw BoltProtocolException(
          'PULL was IGNORED — connection is in a failed state; '
          'send RESET before retrying',
        );
      }
      if (s.tag == BoltTag.success) {
        pullSummary = s.fields.isEmpty
            ? const <String, Object?>{}
            : (s.fields.first as Map).cast<String, Object?>();
        break;
      }
      if (s.tag == BoltTag.record) {
        records.add(BoltRecord((s.fields.first as List).cast<Object?>()));
        first = await _readResponse();
        continue;
      }
      throw BoltProtocolException(
        'unexpected message tag 0x${s.tag.toRadixString(16)} '
        'while pulling result',
      );
    }
    return BoltResult(
      fields: fields,
      records: records,
      summary: pullSummary,
    );
  }

  /// Begin an explicit transaction. The returned [BoltTransaction]
  /// must be committed or rolled back.
  Future<BoltTransaction> beginTransaction({
    Map<String, Object?> extra = const {},
  }) async {
    final reply = await _exchange(beginMessage(extra: extra));
    _expectSuccess(reply, 'BEGIN');
    return BoltTransaction._(this);
  }

  /// Send GOODBYE and close the underlying socket. Safe to call more
  /// than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _writeMessage(goodbyeMessage());
    } catch (_) {
      // Best-effort: server may have already closed.
    }
    await _subscription?.cancel();
    try {
      await _socket.close();
    } catch (_) {/* ignore */}
    _socket.destroy();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _startReader() {
    _subscription = _socket.listen(
      (data) {
        _reassembler.feed(data);
        while (true) {
          final msg = _reassembler.pop();
          if (msg == null) break;
          if (_waiters.isNotEmpty) {
            _waiters.removeAt(0).complete(msg);
          } else {
            _pendingResponses.add(msg);
          }
        }
      },
      onError: (Object e, StackTrace st) {
        _socketError = e;
        for (final w in _waiters) {
          if (!w.isCompleted) w.completeError(e, st);
        }
        _waiters.clear();
      },
      onDone: () {
        for (final w in _waiters) {
          if (!w.isCompleted) {
            w.completeError(
              BoltProtocolException('Bolt connection closed by peer'),
            );
          }
        }
        _waiters.clear();
      },
      cancelOnError: false,
    );
  }

  /// Read the next response body from the connection, awaiting one
  /// from the wire if none is currently buffered.
  Future<BoltStructure> _readResponse() async {
    if (_pendingResponses.isNotEmpty) {
      final body = _pendingResponses.removeAt(0);
      return _decodeResponse(body);
    }
    if (_closed) {
      throw BoltProtocolException('Bolt connection is closed');
    }
    if (_socketError != null) {
      throw BoltProtocolException(
        'Bolt connection is in a failed state',
        cause: _socketError,
      );
    }
    final completer = Completer<Uint8List>();
    _waiters.add(completer);
    final body = await completer.future;
    return _decodeResponse(body);
  }

  BoltStructure _decodeResponse(Uint8List body) {
    final value = PackStreamDecoder(body).unpack();
    if (value is! BoltStructure) {
      throw BoltProtocolException(
        'expected a Bolt response Structure, got ${value.runtimeType}',
      );
    }
    return value;
  }

  Future<BoltStructure> _exchange(BoltStructure message) async {
    if (_closed) {
      throw BoltProtocolException('Bolt connection is closed');
    }
    if (_socketError != null) {
      throw BoltProtocolException(
        'Bolt connection is in a failed state',
        cause: _socketError,
      );
    }
    await _writeMessage(message);
    return _readResponse();
  }

  Future<void> _writeMessage(BoltStructure msg) async {
    final body = packStream(msg);
    // Chunk into ≤ 0xFFFF-byte slices, each preceded by a 2-byte size,
    // and finalize with a `00 00` end-of-message marker.
    final out = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < body.length) {
      final chunkLen = (body.length - offset).clamp(1, _maxChunkBody);
      out
        ..addByte((chunkLen >> 8) & 0xFF)
        ..addByte(chunkLen & 0xFF)
        ..add(body.sublist(offset, offset + chunkLen));
      offset += chunkLen;
    }
    out
      ..addByte(0)
      ..addByte(0);
    _socket.add(out.takeBytes());
    await _socket.flush();
  }

  Map<String, Object?> _expectSuccess(BoltStructure msg, String label) {
    if (msg.tag == BoltTag.failure) {
      _throwFailure(msg);
    }
    if (msg.tag != BoltTag.success) {
      throw BoltProtocolException(
        '$label expected SUCCESS, got tag '
        '0x${msg.tag.toRadixString(16).padLeft(2, '0')}',
      );
    }
    if (msg.fields.isEmpty) return const {};
    final m = msg.fields.first;
    if (m is Map) return m.cast<String, Object?>();
    return const {};
  }

  Never _throwFailure(BoltStructure msg) {
    final m = msg.fields.isEmpty ? const <String, Object?>{} : msg.fields.first;
    if (m is Map) {
      final code = (m['code'] ?? 'Neo.Unknown').toString();
      final message = (m['message'] ?? '').toString();
      throw BoltFailure(code, message);
    }
    throw BoltProtocolException('FAILURE message had no metadata map');
  }

  /// Read the handshake response (4 bytes) before any application
  /// data is exchanged. A pending [_pendingHandshakeBytes] is set up
  /// so we don't have to spin up a temporary listener and risk losing
  /// bytes when handing off to the long-lived reader.
  static Future<Uint8List> _readExactly(Socket socket, int n) {
    final completer = Completer<Uint8List>();
    final out = BytesBuilder(copy: false);
    late StreamSubscription<List<int>> sub;
    sub = socket.listen(
      (data) {
        if (completer.isCompleted) return;
        out.add(data);
        if (out.length >= n) {
          final bytes = out.takeBytes();
          if (bytes.length != n) {
            // Server sent extra bytes — Bolt does not pipeline data
            // onto the handshake response, so this is a protocol
            // violation we surface rather than silently buffer.
            sub.cancel();
            completer.completeError(BoltProtocolException(
              'handshake response had $n bytes expected, got '
              '${bytes.length}',
            ));
            return;
          }
          sub.pause();
          sub.cancel();
          completer.complete(bytes);
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(BoltProtocolException(
            'socket closed before handshake response was read',
          ));
        }
      },
      cancelOnError: true,
    );
    return completer.future;
  }
}

/// Handle for an explicit Bolt transaction.
class BoltTransaction {
  BoltTransaction._(this._connection);

  final BoltConnection _connection;
  bool _settled = false;

  /// Run a statement inside this transaction.
  Future<BoltResult> run(
    String cypher, {
    Map<String, Object?> parameters = const {},
  }) =>
      _connection.runAndPull(cypher, parameters: parameters);

  Future<void> commit() async {
    if (_settled) return;
    _settled = true;
    final reply = await _connection._exchange(commitMessage());
    _connection._expectSuccess(reply, 'COMMIT');
  }

  Future<void> rollback() async {
    if (_settled) return;
    _settled = true;
    final reply = await _connection._exchange(rollbackMessage());
    _connection._expectSuccess(reply, 'ROLLBACK');
  }
}
