import 'package:test_package/src/src.dart';
export 'package:test_package/src/src.dart';
import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';

String libFunction() => "libFunction";

const sourceName = '../isolate_exec_test_package/lib/lib.dart';

@isolateReflector
@sourceName
class DefaultObject implements SomeObjectBaseClass {
  @override
  String get id => "default";
}

@isolateReflector
@sourceName
class PositionalArgumentsObject implements SomeObjectBaseClass {
  PositionalArgumentsObject(this.id);

  @override
  String id;
}

@isolateReflector
@sourceName
class NamedArgumentsObject implements SomeObjectBaseClass {
  NamedArgumentsObject({this.id = ''});

  @override
  String id;
}

@isolateReflector
@sourceName
class NamedConstructorObject implements SomeObjectBaseClass {
  NamedConstructorObject.fromID();

  @override
  String get id => "fromID";
}
