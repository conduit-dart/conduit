import 'dart:collection';

class LowercaseMap<V> extends Object with MapMixin<String, V> {
  LowercaseMap();
  LowercaseMap.fromMap(Map<String, V> m) {
    m.forEach((k, v) {
      _inner[k.toLowerCase()] = v;
    });
  }

  final Map<String, V> _inner = {};

  @override
  Iterable<String> get keys => _inner.keys;

  @override
  V? operator [](covariant Object key) => _inner[key as String];

  @override
  void operator []=(String key, V value) {
    _inner[key.toLowerCase()] = value;
  }

  @override
  void clear() {
    _inner.clear();
  }

  @override
  V? remove(Object? key) => _inner.remove(key);
}
