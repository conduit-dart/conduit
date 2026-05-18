import 'dart:typed_data';

import 'package:conduit_graph_neo4j/conduit_graph_neo4j.dart';
import 'package:test/test.dart';

Uint8List hex(String s) {
  final cleaned = s.replaceAll(RegExp(r'\s+'), '');
  final out = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexOf(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PackStream encode — scalars', () {
    test('null -> 0xC0', () {
      expect(hexOf(packStream(null)), 'c0');
    });

    test('booleans', () {
      expect(hexOf(packStream(true)), 'c3');
      expect(hexOf(packStream(false)), 'c2');
    });

    test('TINY_INT positive (0..127)', () {
      expect(hexOf(packStream(0)), '00');
      expect(hexOf(packStream(1)), '01');
      expect(hexOf(packStream(127)), '7f');
    });

    test('TINY_INT negative (-16..-1)', () {
      expect(hexOf(packStream(-1)), 'ff');
      expect(hexOf(packStream(-16)), 'f0');
    });

    test('INT_8 boundary', () {
      expect(hexOf(packStream(128)), 'c90080');
      // -17 fits in INT_8.
      expect(hexOf(packStream(-17)), 'c8ef');
      expect(hexOf(packStream(-128)), 'c880');
    });

    test('INT_16', () {
      expect(hexOf(packStream(32767)), 'c97fff');
      expect(hexOf(packStream(-32768)), 'c98000');
    });

    test('INT_32', () {
      expect(hexOf(packStream(2147483647)), 'ca7fffffff');
    });

    test('INT_64', () {
      // 2^33.
      expect(hexOf(packStream(8589934592)), 'cb0000000200000000');
    });

    test('Float', () {
      // 1.0 in IEEE 754 big-endian double = 3FF0_0000_0000_0000.
      expect(hexOf(packStream(1.0)), 'c13ff0000000000000');
    });
  });

  group('PackStream encode — strings', () {
    test('TINY_STRING (len 0..15)', () {
      expect(hexOf(packStream('')), '80');
      expect(hexOf(packStream('a')), '8161');
      // Length 5: marker = 0x85, "hello".
      expect(hexOf(packStream('hello')), '8568656c6c6f');
    });

    test('STRING_8 (len 16..255)', () {
      final s = 'a' * 16;
      // Marker 0xD0, size 0x10, then 16 'a' bytes.
      expect(packStream(s).first, 0xD0);
      expect(packStream(s)[1], 0x10);
      expect(packStream(s).length, 1 + 1 + 16);
    });

    test('UTF-8 round-trip', () {
      final v = 'café résumé';
      final encoded = packStream(v);
      expect(unpackStream(encoded), v);
    });
  });

  group('PackStream encode — list / map / structure', () {
    test('TINY_LIST', () {
      // [1, 2, 3] -> 93 01 02 03
      expect(hexOf(packStream([1, 2, 3])), '93010203');
    });

    test('TINY_MAP with string keys', () {
      // {'a': 1} -> A1 81 61 01
      expect(hexOf(packStream({'a': 1})), 'a181' '6101');
    });

    test('TINY_STRUCT round-trip', () {
      final s = BoltStructure(0x70, [
        {'fields': ['n']},
      ]);
      final encoded = packStream(s);
      // First byte: TINY_STRUCT marker 0xB1 (one field).
      expect(encoded.first, 0xB1);
      // Second byte: tag 0x70.
      expect(encoded[1], 0x70);
      final decoded = unpackStream(encoded);
      expect(decoded, isA<BoltStructure>());
      expect((decoded as BoltStructure).tag, 0x70);
      expect(decoded.fields.first, isA<Map>());
    });
  });

  group('PackStream decode', () {
    test('round-trips a complex value', () {
      final original = {
        'name': 'alice',
        'age': 30,
        'active': true,
        'tags': ['a', 'b'],
        'meta': {'x': 1.5, 'y': null},
      };
      final encoded = packStream(original);
      final decoded = unpackStream(encoded);
      expect(decoded, original);
    });

    test('decodes a known SUCCESS message body', () {
      // SUCCESS struct (tag 0x70), 1 field, body { fields: ['n'] }.
      final bytes = hex(
        'b1' // TINY_STRUCT 1
        '70' // tag SUCCESS
        'a1' // TINY_MAP 1
        '86' '6669656c6473' // "fields" (tiny string len 6)
        '91' // TINY_LIST 1
        '81' '6e', // "n"
      );
      final decoded = unpackStream(bytes);
      expect(decoded, isA<BoltStructure>());
      final s = decoded as BoltStructure;
      expect(s.tag, 0x70);
      expect(s.fields.length, 1);
      expect(s.fields.first, {
        'fields': ['n']
      });
    });
  });

  group('Bolt message constructors', () {
    test('HELLO with basic auth', () {
      final s = unpackStream(packStream(
        BoltStructure(0x01, [
          {
            'user_agent': 'test/0.1',
            'scheme': 'basic',
            'principal': 'neo4j',
            'credentials': 'pw',
          }
        ]),
      ));
      expect(s, isA<BoltStructure>());
      expect((s as BoltStructure).tag, 0x01);
    });

    test('PULL with default n=-1', () {
      final s = BoltStructure(0x3F, [
        {'n': -1, 'qid': -1},
      ]);
      final encoded = packStream(s);
      final decoded = unpackStream(encoded);
      expect((decoded as BoltStructure).tag, 0x3F);
      expect((decoded.fields.first as Map)['n'], -1);
    });

    test('GOODBYE has no fields', () {
      final s = BoltStructure(0x02, const []);
      // 0xB0 + tag 0x02.
      expect(hexOf(packStream(s)), 'b002');
    });

    test('RUN tag is 0x10 with 3 fields', () {
      final s = BoltStructure(0x10, ['MATCH (n) RETURN n', {}, {}]);
      final encoded = packStream(s);
      // TINY_STRUCT 3 = 0xB3.
      expect(encoded.first, 0xB3);
      // Tag.
      expect(encoded[1], 0x10);
    });
  });

  group('Tag constants', () {
    test('match Bolt 4.x spec', () {
      expect(BoltTag.hello, 0x01);
      expect(BoltTag.goodbye, 0x02);
      expect(BoltTag.reset, 0x0F);
      expect(BoltTag.run, 0x10);
      expect(BoltTag.begin, 0x11);
      expect(BoltTag.commit, 0x12);
      expect(BoltTag.rollback, 0x13);
      expect(BoltTag.discard, 0x2F);
      expect(BoltTag.pull, 0x3F);
      expect(BoltTag.success, 0x70);
      expect(BoltTag.record, 0x71);
      expect(BoltTag.ignored, 0x7E);
      expect(BoltTag.failure, 0x7F);
    });
  });

  group('PackStream error paths', () {
    test('encoder rejects non-string map keys', () {
      expect(
        () => packStream({1: 'a'}),
        throwsArgumentError,
      );
    });

    test('encoder rejects unsupported runtime types', () {
      expect(
        () => packStream(Symbol('x')),
        throwsArgumentError,
      );
    });

    test('decoder surfaces truncated buffers', () {
      // 0xC9 says "INT_16, 2 bytes follow", but we give only 1.
      final bytes = Uint8List.fromList([0xC9, 0x00]);
      expect(
        () => unpackStream(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('decoder rejects unknown markers', () {
      final bytes = Uint8List.fromList([0xCE]);
      expect(
        () => unpackStream(bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
