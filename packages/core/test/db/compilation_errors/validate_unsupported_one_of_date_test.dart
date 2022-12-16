// ignore_for_file: avoid_catching_errors

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

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
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("compareDateOneOf20162017"));
    }
  });
}
