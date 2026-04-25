import 'package:conduit_runtime/src/exceptions.dart';

const String _listPrefix = 'List<';
const String _mapPrefix = 'Map<String,';

T cast<T>(dynamic input) {
  try {
    var typeString = T.toString();
    if (typeString.endsWith('?')) {
      if (input == null) return null as T;
      typeString = typeString.substring(0, typeString.length - 1);
    }

    if (typeString.startsWith(_listPrefix)) {
      if (input is! List) throw TypeError();
      return switch (typeString) {
        'List<int>' => List<int>.from(input) as T,
        'List<num>' => List<num>.from(input) as T,
        'List<double>' => List<double>.from(input) as T,
        'List<String>' => List<String>.from(input) as T,
        'List<bool>' => List<bool>.from(input) as T,
        'List<int?>' => List<int?>.from(input) as T,
        'List<num?>' => List<num?>.from(input) as T,
        'List<double?>' => List<double?>.from(input) as T,
        'List<String?>' => List<String?>.from(input) as T,
        'List<bool?>' => List<bool?>.from(input) as T,
        'List<Map<String, dynamic>>' =>
          List<Map<String, dynamic>>.from(input) as T,
        _ => input as T,
      };
    }

    if (typeString.startsWith(_mapPrefix)) {
      if (input is! Map) throw TypeError();
      final inputMap = input as Map<String, dynamic>;
      return switch (typeString) {
        'Map<String, int>' => Map<String, int>.from(inputMap) as T,
        'Map<String, num>' => Map<String, num>.from(inputMap) as T,
        'Map<String, double>' => Map<String, double>.from(inputMap) as T,
        'Map<String, String>' => Map<String, String>.from(inputMap) as T,
        'Map<String, bool>' => Map<String, bool>.from(inputMap) as T,
        'Map<String, int?>' => Map<String, int?>.from(inputMap) as T,
        'Map<String, num?>' => Map<String, num?>.from(inputMap) as T,
        'Map<String, double?>' => Map<String, double?>.from(inputMap) as T,
        'Map<String, String?>' => Map<String, String?>.from(inputMap) as T,
        'Map<String, bool?>' => Map<String, bool?>.from(inputMap) as T,
        _ => input as T,
      };
    }

    return input as T;
  } on TypeError {
    throw TypeCoercionException(T, input.runtimeType);
  }
}
