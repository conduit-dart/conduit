import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

class FailingHeterogenous extends ManagedObject<_FH> {}

class _FH {
  @primaryKey
  int? id;

  @Validate.oneOf(["x", 1])
  int? d;
}

void main() {
  test("Heterogenous oneOf", () {
    try {
      ManagedDataModel([FailingHeterogenous]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("_FH.d"));
    }
  });
}
