import 'package:test/test.dart';
import 'package:conduit/conduit.dart';

class FailingDateTime extends ManagedObject<_FDT> {}

class _FDT {
  @primaryKey
  int? id;

  @Validate.compare(greaterThanEqualTo: "19x34")
  DateTime? d;
}

void main() {
  test("DateTime fails to parse", () {
    try {
      ManagedDataModel([FailingDateTime]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("19x34"));
      expect(e.toString(), contains("cannot be parsed as expected"));
      expect(e.toString(), contains("_FDT.d"));
    }
  });
}
