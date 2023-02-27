import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

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
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("is only valid for 'String'"));
      expect(e.toString(), contains("_FRX.d"));
    }
  });
}
