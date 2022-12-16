import 'package:conduit_core/src/db/managed/data_model.dart';
import 'package:conduit_core/src/db/managed/entity.dart';
import 'package:conduit_core/src/utilities/reference_counting_list.dart';

ReferenceCountingList<ManagedDataModel> dataModels =
    ReferenceCountingList<ManagedDataModel>();

ManagedEntity findEntity(
  Type type, {
  ManagedEntity Function()? orElse,
}) {
  for (final d in dataModels) {
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

void add(ManagedDataModel model) {
  final idx = dataModels.indexOf(model);
  if (idx == -1) {
    dataModels.add(model);
  }

  model.retain();
}
