import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

class AutoincrementAndDefault extends ManagedObject<_AutoincrementAndDefault> {}

class _AutoincrementAndDefault {
  @primaryKey
  int? id;

  @Column(autoincrement: true, defaultValue: "1")
  int? i;
}

void main() {
  test("Property is both autoincrement and default value, fails", () {
    try {
      final _ = ManagedDataModel([AutoincrementAndDefault]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("_AutoincrementAndDefault.i"));
      expect(e.message, contains("autoincrement"));
      expect(e.message, contains("default value"));
    }
  });
}
