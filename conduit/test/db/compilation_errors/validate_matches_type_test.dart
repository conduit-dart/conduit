import 'package:test/test.dart';
import 'package:conduit/conduit.dart';

class FailingRegex extends ManagedObject<_FRX> {}

class _FRX {
  @primaryKey
  int? id;

  @Validate.matches("xyz")
  int? d;
}

void main() {
  test("Non-string Validate.matches", () {
    try {
      ManagedDataModel([FailingRegex]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("is only valid for 'String'"));
      expect(e.toString(), contains("_FRX.d"));
    }
  });
}
