// ignore_for_file: avoid_catching_errors

import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  test(
      "Add Table to table definition with non-existent property in unique list throws exception",
      () {
    try {
      ManagedDataModel([MultiUniqueFailureUnknown]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("'a' is not a property of this type"));
    }
  });
}

class MultiUniqueFailureUnknown
    extends ManagedObject<_MultiUniqueFailureUnknown> {}

@Table.unique([Symbol('a'), Symbol('b')])
class _MultiUniqueFailureUnknown {
  @primaryKey
  int? id;

  int? b;
}
