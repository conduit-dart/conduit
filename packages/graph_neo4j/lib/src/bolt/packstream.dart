// PackStream codec for the Bolt v4.x protocol.
//
// Scope of this implementation
// ----------------------------
// We support the subset of PackStream that Bolt 4.4 message bodies and
// query parameters / RECORD payloads actually use:
//
//   - Null, Bool
//   - Int (TINY_INT, INT_8, INT_16, INT_32, INT_64)
//   - Float (Float64)
//   - String (TINY_STRING, STRING_8/16/32)
//   - List (TINY_LIST, LIST_8/16/32)
//   - Dictionary (TINY_MAP, MAP_8/16/32, string-keyed only)
//   - Structure (TINY_STRUCT, STRUCT_8 — STRUCT_16 is not used by Bolt 4.x
//     because no message has more than 15 top-level fields, but we
//     still recognize it on decode for forwards-compat)
//
// We do *not* implement: bytes (Bolt-spec only, not used by parameters
// in Bolt 4.x), 2D/3D points, dates, durations, or any of the temporal
// structs. The Neo4j server returns datetimes as structures with tag
// bytes 0x44 / 0x46 / 0x49 / etc.; on decode we surface those as
// `BoltStructure` values so the caller can map them. On encode the
// caller is responsible for marshaling a Dart `DateTime` to whatever
// representation the query expects (an ISO-8601 string is the simplest).
//
// This is intentionally a small, single-purpose codec. It is not a
// general-purpose msgpack-shaped serializer.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A PackStream Structure — a tagged tuple of fields.
///
/// Bolt messages are themselves Structures (tagged with the message
/// kind, e.g. 0x01 for HELLO). Server-side responses for nodes,
/// relationships, paths and temporal types arrive as Structures too.
class BoltStructure {
  BoltStructure(this.tag, List<Object?> fields)
      : fields = List.unmodifiable(fields);

  final int tag;
  final List<Object?> fields;

  @override
  String toString() =>
      'BoltStructure(tag=0x${tag.toRadixString(16).padLeft(2, '0')}, '
      'fields=$fields)';
}

/// PackStream encoder.
///
/// Stateful so the caller can stream a sequence of values into a
/// growing buffer (a Bolt message is a single Structure, but its
/// fields may themselves be lists / maps that we recurse into).
class PackStreamEncoder {
  final BytesBuilder _out = BytesBuilder(copy: false);

  Uint8List takeBytes() => _out.takeBytes();

  int get length => _out.length;

  void pack(Object? value) {
    if (value == null) {
      _out.addByte(0xC0);
      return;
    }
    if (value is bool) {
      _out.addByte(value ? 0xC3 : 0xC2);
      return;
    }
    if (value is int) {
      _packInt(value);
      return;
    }
    if (value is double) {
      _packFloat(value);
      return;
    }
    if (value is String) {
      _packString(value);
      return;
    }
    if (value is List) {
      _packList(value);
      return;
    }
    if (value is Map) {
      _packMap(value);
      return;
    }
    if (value is BoltStructure) {
      _packStructure(value);
      return;
    }
    if (value is DateTime) {
      // Convenience: marshal DateTime as ISO-8601 UTC string so query
      // parameters Just Work without forcing the user to call
      // `.toIso8601String()` themselves.
      _packString(value.toUtc().toIso8601String());
      return;
    }
    throw ArgumentError.value(
      value,
      'value',
      'PackStream cannot encode runtime type ${value.runtimeType}',
    );
  }

  void _packInt(int v) {
    if (v >= -16 && v <= 127) {
      // TINY_INT: value encoded directly as a single signed byte.
      _out.addByte(v & 0xFF);
      return;
    }
    if (v >= -0x80 && v <= 0x7F) {
      _out.addByte(0xC8);
      _out.addByte(v & 0xFF);
      return;
    }
    if (v >= -0x8000 && v <= 0x7FFF) {
      _out.addByte(0xC9);
      final b = ByteData(2)..setInt16(0, v, Endian.big);
      _out.add(b.buffer.asUint8List());
      return;
    }
    if (v >= -0x80000000 && v <= 0x7FFFFFFF) {
      _out.addByte(0xCA);
      final b = ByteData(4)..setInt32(0, v, Endian.big);
      _out.add(b.buffer.asUint8List());
      return;
    }
    // INT_64.
    _out.addByte(0xCB);
    final b = ByteData(8)..setInt64(0, v, Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _packFloat(double v) {
    _out.addByte(0xC1);
    final b = ByteData(8)..setFloat64(0, v, Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _packString(String v) {
    final bytes = utf8.encode(v);
    final n = bytes.length;
    if (n <= 15) {
      _out.addByte(0x80 | n);
    } else if (n <= 0xFF) {
      _out.addByte(0xD0);
      _out.addByte(n);
    } else if (n <= 0xFFFF) {
      _out.addByte(0xD1);
      final b = ByteData(2)..setUint16(0, n, Endian.big);
      _out.add(b.buffer.asUint8List());
    } else {
      _out.addByte(0xD2);
      final b = ByteData(4)..setUint32(0, n, Endian.big);
      _out.add(b.buffer.asUint8List());
    }
    _out.add(bytes);
  }

  void _packList(List<Object?> items) {
    final n = items.length;
    if (n <= 15) {
      _out.addByte(0x90 | n);
    } else if (n <= 0xFF) {
      _out.addByte(0xD4);
      _out.addByte(n);
    } else if (n <= 0xFFFF) {
      _out.addByte(0xD5);
      final b = ByteData(2)..setUint16(0, n, Endian.big);
      _out.add(b.buffer.asUint8List());
    } else {
      _out.addByte(0xD6);
      final b = ByteData(4)..setUint32(0, n, Endian.big);
      _out.add(b.buffer.asUint8List());
    }
    for (final item in items) {
      pack(item);
    }
  }

  void _packMap(Map<Object?, Object?> m) {
    final n = m.length;
    if (n <= 15) {
      _out.addByte(0xA0 | n);
    } else if (n <= 0xFF) {
      _out.addByte(0xD8);
      _out.addByte(n);
    } else if (n <= 0xFFFF) {
      _out.addByte(0xD9);
      final b = ByteData(2)..setUint16(0, n, Endian.big);
      _out.add(b.buffer.asUint8List());
    } else {
      _out.addByte(0xDA);
      final b = ByteData(4)..setUint32(0, n, Endian.big);
      _out.add(b.buffer.asUint8List());
    }
    m.forEach((k, v) {
      if (k is! String) {
        throw ArgumentError.value(
          k,
          'key',
          'PackStream dictionaries are string-keyed; got ${k.runtimeType}',
        );
      }
      _packString(k);
      pack(v);
    });
  }

  void _packStructure(BoltStructure s) {
    final n = s.fields.length;
    if (n <= 15) {
      _out.addByte(0xB0 | n);
    } else if (n <= 0xFF) {
      _out.addByte(0xDC);
      _out.addByte(n);
    } else {
      throw ArgumentError(
        'Structure with ${s.fields.length} fields exceeds PackStream limits',
      );
    }
    if (s.tag < 0 || s.tag > 0x7F) {
      throw ArgumentError('Structure tag must be in 0..0x7F, got 0x'
          '${s.tag.toRadixString(16)}');
    }
    _out.addByte(s.tag);
    for (final f in s.fields) {
      pack(f);
    }
  }
}

/// PackStream decoder.
///
/// Reads from a fixed [Uint8List] cursor. Bolt-level chunk reassembly
/// happens in `BoltConnection`; this decoder works on the assembled
/// message body.
class PackStreamDecoder {
  PackStreamDecoder(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  bool get hasMore => _pos < _bytes.length;
  int get position => _pos;

  Object? unpack() {
    if (_pos >= _bytes.length) {
      throw FormatException(
        'PackStream: unexpected end of buffer at offset $_pos',
      );
    }
    final marker = _bytes[_pos++];

    // TINY_INT positive: 0x00..0x7F
    if (marker <= 0x7F) {
      return marker;
    }
    // TINY_INT negative: 0xF0..0xFF (-16..-1)
    if (marker >= 0xF0) {
      return marker - 0x100;
    }
    // TINY_STRING: 0x80..0x8F
    if ((marker & 0xF0) == 0x80) {
      return _readUtf8(marker & 0x0F);
    }
    // TINY_LIST: 0x90..0x9F
    if ((marker & 0xF0) == 0x90) {
      return _readList(marker & 0x0F);
    }
    // TINY_MAP: 0xA0..0xAF
    if ((marker & 0xF0) == 0xA0) {
      return _readMap(marker & 0x0F);
    }
    // TINY_STRUCT: 0xB0..0xBF
    if ((marker & 0xF0) == 0xB0) {
      return _readStructure(marker & 0x0F);
    }

    switch (marker) {
      case 0xC0:
        return null;
      case 0xC1:
        return _readFloat();
      case 0xC2:
        return false;
      case 0xC3:
        return true;
      case 0xC8:
        return _readInt(1);
      case 0xC9:
        return _readInt(2);
      case 0xCA:
        return _readInt(4);
      case 0xCB:
        return _readInt(8);
      case 0xD0:
        return _readUtf8(_readUint(1));
      case 0xD1:
        return _readUtf8(_readUint(2));
      case 0xD2:
        return _readUtf8(_readUint(4));
      case 0xD4:
        return _readList(_readUint(1));
      case 0xD5:
        return _readList(_readUint(2));
      case 0xD6:
        return _readList(_readUint(4));
      case 0xD8:
        return _readMap(_readUint(1));
      case 0xD9:
        return _readMap(_readUint(2));
      case 0xDA:
        return _readMap(_readUint(4));
      case 0xDC:
        return _readStructure(_readUint(1));
      case 0xDD:
        return _readStructure(_readUint(2));
      default:
        throw FormatException(
          'PackStream: unknown marker 0x'
          '${marker.toRadixString(16).padLeft(2, '0')} '
          'at offset ${_pos - 1}',
        );
    }
  }

  int _readUint(int width) {
    final v = _readBytes(width);
    var out = 0;
    for (var i = 0; i < width; i++) {
      out = (out << 8) | v[i];
    }
    return out;
  }

  int _readInt(int width) {
    final bytes = _readBytes(width);
    final bd = ByteData.sublistView(bytes);
    switch (width) {
      case 1:
        return bd.getInt8(0);
      case 2:
        return bd.getInt16(0, Endian.big);
      case 4:
        return bd.getInt32(0, Endian.big);
      case 8:
        return bd.getInt64(0, Endian.big);
      default:
        throw StateError('unreachable: int width $width');
    }
  }

  double _readFloat() {
    final bytes = _readBytes(8);
    return ByteData.sublistView(bytes).getFloat64(0, Endian.big);
  }

  String _readUtf8(int len) {
    final bytes = _readBytes(len);
    return utf8.decode(bytes);
  }

  List<Object?> _readList(int len) {
    final items = <Object?>[];
    for (var i = 0; i < len; i++) {
      items.add(unpack());
    }
    return items;
  }

  Map<String, Object?> _readMap(int len) {
    final m = <String, Object?>{};
    for (var i = 0; i < len; i++) {
      final k = unpack();
      if (k is! String) {
        throw FormatException(
          'PackStream: expected string key, got ${k.runtimeType}',
        );
      }
      m[k] = unpack();
    }
    return m;
  }

  BoltStructure _readStructure(int len) {
    if (_pos >= _bytes.length) {
      throw FormatException('PackStream: missing structure tag');
    }
    final tag = _bytes[_pos++];
    final fields = <Object?>[];
    for (var i = 0; i < len; i++) {
      fields.add(unpack());
    }
    return BoltStructure(tag, fields);
  }

  Uint8List _readBytes(int n) {
    if (_pos + n > _bytes.length) {
      throw FormatException(
        'PackStream: tried to read $n bytes at offset $_pos, only '
        '${_bytes.length - _pos} remain',
      );
    }
    final out = Uint8List.sublistView(_bytes, _pos, _pos + n);
    _pos += n;
    return out;
  }
}

/// Convenience: encode [value] to a fresh byte buffer.
Uint8List packStream(Object? value) {
  final enc = PackStreamEncoder()..pack(value);
  return enc.takeBytes();
}

/// Convenience: decode a single value from [bytes].
Object? unpackStream(Uint8List bytes) {
  return PackStreamDecoder(bytes).unpack();
}
