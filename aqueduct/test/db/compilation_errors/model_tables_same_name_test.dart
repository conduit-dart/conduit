import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Two entities with same tableName should throw exception", () {
    try {
      var _ = ManagedDataModel([SameNameOne, SameNameTwo]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("SameNameOne"));
      expect(e.message, contains("SameNameTwo"));
      expect(e.message, contains("'fo'"));
    }
  });
}

class SameNameOne extends ManagedObject<_SameNameOne> {}

@Table(name: "fo")
class _SameNameOne {
  @primaryKey
  int id;
}

class SameNameTwo extends ManagedObject<_SameNameTwo> {}

@Table(name: "fo")
class _SameNameTwo {
  @primaryKey
  int id;
}
