import 'dart:mirrors';

import 'package:aqueduct/src/auth/auth.dart';
import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/http/resource_controller_scope.dart';

bool isOperation(DeclarationMirror m) {
  return getMethodOperationMetadata(m) != null;
}

List<AuthScope>? getMethodScopes(DeclarationMirror m) {
  if (!isOperation(m)) {
    return null;
  }

  final method = m as MethodMirror;
  try {
    final metadata = method.metadata
        .firstWhere((im) => im.reflectee is Scope)
        .reflectee as Scope;

    return metadata.scopes.map((scope) => AuthScope(scope)).toList();
  } on StateError {
    return null;
  }
}

Operation? getMethodOperationMetadata(DeclarationMirror m) {
  if (m is! MethodMirror) {
    return null;
  }

  final method = m;
  if (!method.isRegularMethod || method.isStatic) {
    return null;
  }

  try {
    return method.metadata
        .firstWhere((im) => im.reflectee is Operation)
        .reflectee as Operation;
  } on StateError {
    return null;
  }
}
