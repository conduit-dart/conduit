import 'package:conduit_core/src/db/managed/data_model.dart';
import 'package:conduit_core/src/db/managed/entity.dart';

Map<ManagedDataModel, int> _dataModels = {};

ManagedEntity findEntity(
  Type type, {
  ManagedEntity Function()? orElse,
}) {
  for (final d in _dataModels.keys) {
    final entity = d.tryEntityForType(type);
    if (entity != null) {
      return entity;
    }
  }

  if (orElse == null) {
    throw StateError(
      "No entity found for '$type. Did you forget to create a 'ManagedContext'?",
    );
  }

  return orElse();
}

void add(ManagedDataModel dataModel) {
  _dataModels.update(dataModel, (count) => count + 1, ifAbsent: () => 1);
}

void remove(ManagedDataModel dataModel) {
  if (_dataModels[dataModel] != null) {
    _dataModels.update(dataModel, (count) => count - 1);
    if (_dataModels[dataModel]! < 1) {
      _dataModels.remove(dataModel);
    }
  }
}
