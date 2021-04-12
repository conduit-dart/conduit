import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

class NoPrimaryKey extends ManagedObject<_NoPrimaryKey>
    implements _NoPrimaryKey {}

class _NoPrimaryKey {
  String? foo;
}

void main() {
  test("Entity without primary key fails", () {
    try {
      ManagedDataModel([NoPrimaryKey]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(
          e.message,
          contains(
              "Class '_NoPrimaryKey' doesn't declare a primary key property"));
    }
  });
}
