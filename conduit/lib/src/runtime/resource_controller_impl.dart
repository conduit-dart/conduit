import 'dart:async';

import 'package:conduit/src/http/request_body.dart';
import 'package:conduit/src/http/resource_controller.dart';
import 'package:conduit/src/http/resource_controller_bindings.dart';
import 'package:conduit/src/http/resource_controller_interfaces.dart';
import 'package:conduit/src/http/response.dart';
import 'package:conduit/src/http/serializable.dart';
import 'package:conduit/src/runtime/resource_controller/documenter.dart';
import 'package:conduit/src/runtime/resource_controller/utility.dart';
import 'package:conduit/src/runtime/resource_controller_generator.dart';
import 'package:conduit/src/utilities/mirror_helpers.dart';
import 'package:conduit_runtime/runtime.dart' hide firstMetadataOfType;
import 'package:reflectable/reflectable.dart';

class ResourceControllerRuntimeImpl extends ResourceControllerRuntime {
  ResourceControllerRuntimeImpl(this.type) {
    final allDeclarations = type.declarations;

    ivarParameters = allDeclarations.values
        .whereType<VariableMirror>()
        .where((decl) => decl.metadata.any((im) => im is Bind))
        .map((decl) {
      final isRequired = allDeclarations[decl.simpleName]!
          .metadata
          .any((im) => im is RequiredBinding);
      return getParameterForVariable(decl, isRequired: isRequired);
    }).toList();

    operations = type.declarations.values
        .where(isOperation)
        .map((m) => m as MethodMirror)
        .map(getOperationForMethod)
        .toList();

    if (conflictingOperations.isNotEmpty) {
      final opNames = conflictingOperations.map((s) => "'$s'").join(", ");
      throw StateError(
          "Invalid controller. Controller '${type.reflectedType.toString()}' has "
          "ambiguous operations. Offending operating methods: $opNames.");
    }

    if (unsatisfiableOperations.isNotEmpty) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw StateError(
          "Invalid controller. Controller '${type.reflectedType.toString()}' has operations where "
          "parameter is bound with @Bind.path(), but path variable is not declared in "
          "@Operation(). Offending operation methods: $opNames");
    }

    documenter = ResourceControllerDocumenterImpl(this);
  }

  final ClassMirror type;

  String compile(BuildContext ctx) =>
      getResourceControllerImplSource(ctx, this);

  List<String> get directives {
    final directives = <String>[];
    operations.forEach((op) {
      final imports = [
        op.positionalParameters,
        op.namedParameters,
        ivarParameters
      ]
          .expand((i) => i!)
          .map((p) => runtimeReflector.reflectType(p.type).location.sourceUri)
          .where((uri) =>
              uri.scheme == "package" ||
              (uri.scheme == "file" && uri.isAbsolute))
          .map((uri) => "import '$uri';")
          .toList();
      directives.addAll(imports);
    });
    return directives;
  }

  List<String> get unsatisfiableOperations {
    return operations
        .where((op) {
          final argPathParameters = op.positionalParameters
              .where((p) => p.location == BindingType.path);

          return !argPathParameters
              .every((p) => op.pathVariables.contains(p.name));
        })
        .map((op) => op.dartMethodName)
        .toList();
  }

  List<String> get conflictingOperations {
    return operations
        .where((op) {
          final possibleConflicts = operations.where((b) => b != op);

          return possibleConflicts.any((opToCompare) {
            if (opToCompare.httpMethod != op.httpMethod) {
              return false;
            }

            if (opToCompare.pathVariables.length != op.pathVariables.length) {
              return false;
            }

            return opToCompare.pathVariables
                .every((p) => op.pathVariables.contains(p));
          });
        })
        .map((op) => op.dartMethodName)
        .toList();
  }

  @override
  void applyRequestProperties(ResourceController untypedController,
      ResourceControllerOperationInvocationArgs args) {
    final rcMirror = runtimeReflector.reflect(untypedController);

    args.instanceVariables.forEach(rcMirror.invokeSetter);
  }

  ResourceControllerParameter getParameterForVariable(VariableMirror mirror,
      {required bool isRequired}) {
    final metadata = mirror.metadata.firstWhere((im) => im is Bind) as Bind;

    if (mirror.type is! ClassMirror) {
      throw _makeError(mirror, "Cannot bind dynamic parameters.");
    }

    final boundType = mirror.type.reflectedType;
    final boundTypeMirror = runtimeReflector.reflectType(boundType);
    dynamic Function(dynamic input)? decoder;

    switch (metadata.bindingType) {
      case BindingType.body:
        {
          final isDecodingSerializable = isSerializable(boundType);
          final isDecodingListOfSerializable = isListSerializable(boundType);
          if (metadata.ignore != null ||
              metadata.reject != null ||
              metadata.require != null ||
              metadata.accept != null) {
            if (!(isDecodingSerializable || isDecodingListOfSerializable)) {
              throw _makeError(mirror,
                  "Filters can only be used on Serializable or List<Serializable>.");
            }
          }

          if (isDecodingSerializable) {
            decoder = (b) {
              final body = b as RequestBody;

              final value = (boundTypeMirror as ClassMirror).newInstance("", [])
                  as Serializable;
              value.read(body.as(),
                  accept: metadata.accept,
                  ignore: metadata.ignore,
                  reject: metadata.reject,
                  require: metadata.require);

              return value;
            };
          } else if (isDecodingListOfSerializable) {
            decoder = (b) {
              final body = b as RequestBody;
              final bodyList = body.as<List<Map<String, dynamic>>>();
              if (bodyList.isEmpty) {
                return (boundTypeMirror as ClassMirror)
                    .newInstance('from', [[]]);
              }

              final typeArg = runtimeReflector
                  .reflectType(boundType)
                  .typeArguments
                  .first as ClassMirror;
              final iterable = bodyList.map((object) {
                final value = typeArg.newInstance("", []) as Serializable;
                value.read(object,
                    accept: metadata.accept,
                    ignore: metadata.ignore,
                    reject: metadata.reject,
                    require: metadata.require);

                return value;
              }).toList();

              return (boundTypeMirror as ClassMirror)
                  .newInstance('from', [iterable]);
            };
          } else {
            decoder = (b) {
              final body = b as RequestBody;
              return runtimeCast(body.as(), boundType);
            };
          }
        }
        break;
      case BindingType.query:
        {
          final isListOfBools = runtimeReflector
                  .reflectType(boundType)
                  .isAssignableTo(runtimeReflector.reflectType(List)) &&
              runtimeReflector
                  .reflectType(boundType)
                  .typeArguments
                  .first
                  .isAssignableTo(runtimeReflector.reflectType(bool));

          if (!(boundTypeMirror
                  .isAssignableTo(runtimeReflector.reflectType(bool)) ||
              isListOfBools)) {
            if (boundTypeMirror
                .isAssignableTo(runtimeReflector.reflectType(List))) {
              _enforceTypeCanBeParsedFromString(
                  mirror, boundTypeMirror.typeArguments.first);
            } else {
              _enforceTypeCanBeParsedFromString(mirror, boundTypeMirror);
            }
          }
          decoder = (value) {
            return _convertParameterListWithMirror(
                value as List<String>?, boundTypeMirror);
          };
        }
        break;
      case BindingType.path:
        {
          if (boundTypeMirror
              .isAssignableTo(runtimeReflector.reflectType(List))) {
            throw _makeError(mirror,
                "Cannot bind variable of type 'List' to path parameter.");
          }
          decoder = (value) {
            return _convertParameterWithMirror(value as String?, mirror.type);
          };
        }
        break;
      case BindingType.header:
        {
          if (boundTypeMirror
              .isAssignableTo(runtimeReflector.reflectType(List))) {
            _enforceTypeCanBeParsedFromString(
                mirror, boundTypeMirror.typeArguments.first);
          } else {
            _enforceTypeCanBeParsedFromString(mirror, boundTypeMirror);
          }
          decoder = (value) {
            return _convertParameterListWithMirror(
                value as List<String>?, mirror.type);
          };
        }
        break;
    }

    return ResourceControllerParameter(
        acceptFilter: metadata.accept,
        ignoreFilter: metadata.ignore,
        rejectFilter: metadata.reject,
        requireFilter: metadata.require,
        name: metadata.name,
        type: mirror.type.reflectedType,
        symbolName: mirror.simpleName,
        location: metadata.bindingType,
        isRequired: isRequired,
        decoder: decoder,
        defaultValue: (mirror is ParameterMirror) ? mirror.defaultValue : null);
  }

  ResourceControllerOperation getOperationForMethod(MethodMirror mirror) {
    final operation = getMethodOperationMetadata(mirror)!;
    final symbol = mirror.simpleName;

    final parametersWithoutMetadata = mirror.parameters
        .where((p) => firstMetadataOfType<Bind>(p) == null)
        .toList();
    if (parametersWithoutMetadata.isNotEmpty) {
      final names =
          parametersWithoutMetadata.map((p) => "'${p.simpleName}'").join(", ");
      throw StateError("Invalid operation method parameter(s) $names on "
          "'${getMethodAndClassName(parametersWithoutMetadata.first)}': Must have @Bind annotation.");
    }

    return ResourceControllerOperation(
        positionalParameters: mirror.parameters
            .where((pm) => !pm.isOptional)
            .map((pm) => getParameterForVariable(pm, isRequired: true))
            .toList(),
        namedParameters: mirror.parameters
            .where((pm) => pm.isOptional)
            .map((pm) => getParameterForVariable(
                  pm,
                  isRequired: false,
                ))
            .toList(),
        scopes: getMethodScopes(mirror),
        dartMethodName: symbol,
        httpMethod: operation.method.toUpperCase(),
        pathVariables: operation.pathVariables,
        invoker: (rc, args) {
          return runtimeReflector.reflect(rc).invoke(
                  symbol,
                  args.positionalArguments,
                  args.namedArguments.map((k, v) => MapEntry(Symbol(k), v)))
              as Future<Response>?;
        });
  }
}

StateError _makeError(VariableMirror mirror, String s) {
  return StateError("Invalid binding '${mirror.simpleName}' "
      "on '${getMethodAndClassName(mirror)}':$s");
}

void _enforceTypeCanBeParsedFromString(
    VariableMirror varMirror, TypeMirror typeMirror) {
  if (typeMirror is! ClassMirror) {
    throw _makeError(varMirror, 'Cannot bind dynamic type parameters.');
  }

  if (typeMirror.isAssignableTo(runtimeReflector.reflectType(String))) {
    return;
  }

  final classMirror = typeMirror;
  if (!classMirror.staticMembers.containsKey(#parse)) {
    throw _makeError(
        varMirror, 'Parameter type does not implement static parse method.');
  }

  final parseMethod = classMirror.staticMembers[#parse]!;
  final params = parseMethod.parameters.where((p) => !p.isOptional).toList();
  if (params.length == 1 &&
      params.first.type.isAssignableTo(runtimeReflector.reflectType(String))) {
    return;
  }

  throw _makeError(varMirror, 'Invalid parameter type.');
}

dynamic _convertParameterListWithMirror(
    List<String>? parameterValues, TypeMirror typeMirror) {
  if (typeMirror.isSubtypeOf(runtimeReflector.reflectType(List))) {
    final iterable = parameterValues!.map((str) =>
        _convertParameterWithMirror(str, typeMirror.typeArguments.first));

    return (typeMirror as ClassMirror).newInstance('from', [iterable]);
  } else {
    if (parameterValues == null) {
      print('wtf');
    }
    if (parameterValues!.length > 1) {
      throw ArgumentError("multiple values not expected");
    }
    return _convertParameterWithMirror(parameterValues.first, typeMirror);
  }
}

dynamic _convertParameterWithMirror(
    String? parameterValue, TypeMirror typeMirror) {
  if (typeMirror.isSubtypeOf(runtimeReflector.reflectType(bool))) {
    return true;
  }

  if (typeMirror.isSubtypeOf(runtimeReflector.reflectType(String))) {
    return parameterValue;
  }

  final classMirror = typeMirror as ClassMirror;
  final parseDecl = classMirror.declarations[#parse]!;
  try {
    return classMirror.invoke(parseDecl.simpleName, [parameterValue]);
  } catch (_) {
    throw ArgumentError("invalid value");
  }
}
