import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

class InvalidTransientModel extends ManagedObject<_InvalidTransientModel>
    implements _InvalidTransientModel {
  @Serialize()
  Uri? uri;
}

class _InvalidTransientModel {
  @primaryKey
  int? id;
}

void main() {
  test("Model with unsupported transient property type fails on compilation",
      () {
    try {
      ManagedDataModel([InvalidTransientModel]);
      fail('unreachable');
      // ignore: avoid_catching_errors
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("'InvalidTransientModel'"));
      expect(e.message, contains("'uri'"));
      expect(e.message, contains("unsupported type"));
    }
  });
}
