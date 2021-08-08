import 'package:collection/collection.dart' show IterableExtension;
import 'package:conduit/src/auth/auth.dart';
import 'package:conduit/src/http/http.dart';
import 'package:conduit/src/http/resource_controller_bindings.dart';
import 'package:conduit/src/http/resource_controller_scope.dart';
import 'package:reflectable/reflectable.dart';

bool isOperation(DeclarationMirror m) {
  return getMethodOperationMetadata(m as MethodMirror) != null;
}

List<AuthScope>? getMethodScopes(DeclarationMirror m) {
  if (!isOperation(m)) {
    return null;
  }

  final method = m as MethodMirror;
  final metadata =
      method.metadata.firstWhereOrNull((im) => im is Scope) as Scope?;

  return metadata?.scopes.map((scope) => AuthScope(scope)).toList();
}

Operation? getMethodOperationMetadata(MethodMirror m) {
  if (m is! MethodMirror) {
    return null;
  }

  final method = m;
  if (!method.isRegularMethod || method.isStatic) {
    return null;
  }

  final metadata =
      method.metadata.firstWhereOrNull((im) => im is Operation) as Operation?;

  return metadata;
}
