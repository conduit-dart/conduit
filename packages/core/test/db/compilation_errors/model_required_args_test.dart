import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  test("Cannot have unnamed constructor with required args", () {
    try {
      ManagedDataModel([DefaultConstructorHasRequiredArgs]);
      fail('unreachable');
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("DefaultConstructorHasRequiredArgs"));
      expect(e.toString(), contains("default, unnamed constructor"));
    }
  });
}

class DefaultConstructorHasRequiredArgs(int foo)
    extends ManagedObject<_ConstructorTableDef>;

class _ConstructorTableDef {
  @primaryKey
  int? id;
}
