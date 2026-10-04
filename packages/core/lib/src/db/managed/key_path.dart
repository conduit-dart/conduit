import 'package:conduit_core/src/db/managed/managed.dart';

class KeyPath {
  new(ManagedPropertyDescription? root) : path = [root];

  new byRemovingFirstNKeys(KeyPath original, int offset)
    : path = original.path.sublist(offset);

  new byAddingKey(KeyPath original, ManagedPropertyDescription key)
    : path = List.from(original.path)..add(key);

  final List<ManagedPropertyDescription?> path;
  List<dynamic>? dynamicElements;

  ManagedPropertyDescription? operator [](int index) => path[index];

  int get length => path.length;

  void add(ManagedPropertyDescription element) {
    path.add(element);
  }

  void addDynamicElement(dynamic element) {
    dynamicElements ??= [];
    dynamicElements!.add(element);
  }
}
