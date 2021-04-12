import 'package:test/test.dart';
import 'package:conduit/conduit.dart';

class UnsupportedDateOneOf extends ManagedObject<_UDAOO> {}

class _UDAOO {
  @primaryKey
  int? id;

  @Validate.oneOf(["2016-01-01T00:00:00", "2017-01-01T00:00:00"])
  DateTime? compareDateOneOf20162017;
}

void main() {
  test("Unsupported type, date, for oneOf", () {
    try {
      ManagedDataModel([UnsupportedDateOneOf]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("compareDateOneOf20162017"));
    }
  });
}
