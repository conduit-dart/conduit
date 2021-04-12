import 'package:test/test.dart';
import 'package:conduit/conduit.dart';

class FailingLength extends ManagedObject<_FLEN> {}

class _FLEN {
  @primaryKey
  int? id;

  @Validate.length(equalTo: 6)
  int? d;
}

void main() {
  test("Non-string Validate.length", () {
    try {
      ManagedDataModel([FailingLength]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("is only valid for 'String'"));
      expect(e.toString(), contains("_FLEN.d"));
    }
  });
}
