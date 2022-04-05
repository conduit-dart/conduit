import 'package:test_package/src/src.dart';
export 'package:test_package/src/src.dart';

String libFunction() => "libFunction";

class DefaultObject implements SomeObjectBaseClass {
  @override
  String get id => "default";
}

class PositionalArgumentsObject implements SomeObjectBaseClass {
  PositionalArgumentsObject(this.id);

  @override
  String id;
}

class NamedArgumentsObject implements SomeObjectBaseClass {
  NamedArgumentsObject({this.id = ''});

  @override
  String id;
}

class NamedConstructorObject implements SomeObjectBaseClass {
  NamedConstructorObject.fromID();

  @override
  String get id => "fromID";
}
