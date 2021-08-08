import 'package:reflectable/reflectable.dart';

const sourceName = '../isolate_exec/lib/src/reflector.dart';

@isolateReflector
@sourceName
class IsolateReflector extends Reflectable {
  const IsolateReflector()
      : super(
          newInstanceCapability,
          invokingCapability,
          instanceInvokeCapability,
          declarationsCapability,
          typingCapability,
          libraryCapability,
          superclassQuantifyCapability,
          reflectedTypeCapability,
        );
}

const isolateReflector = IsolateReflector();
