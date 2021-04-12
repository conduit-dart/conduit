import 'package:test/test.dart';
import 'package:conduit/conduit.dart';

class FailingOneOf extends ManagedObject<_FOO> {}

class _FOO {
  @primaryKey
  int? id;

  @Validate.oneOf(["x", "y"])
  int? d;
}

void main() {
  test("Non-matching type for oneOf", () {
    try {
      ManagedDataModel([FailingOneOf]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("_FOO.d"));
    }
  });
}
