import 'dart:mirrors';

import 'package:conduit_core/src/application/channel.dart';
import 'package:conduit_core/src/http/controller.dart';
import 'package:conduit_core/src/http/serializable.dart';
import 'package:conduit_core/src/runtime/impl.dart';
import 'package:conduit_core/src/runtime/orm/data_model_compiler.dart';
import 'package:conduit_runtime/dev.dart';

/// Discovers conduit_core's runtime types via `dart:mirrors` for the
/// JIT/dev fallback. Under AOT, the build_runner-generated `bootstrap()`
/// installs the registry directly and this class is unreachable.
///
/// The mirror surface used to also drive `conduit build`'s pubspec
/// deflection (`deflectPackage`, `getUrisToResolve`,
/// `didFinishPackageGeneration`); those hooks were removed when
/// `conduit build` was retired.
class ConduitCompiler extends Compiler {
  @override
  Map<String, Object> compile(MirrorContext context) {
    final m = <String, Object>{};

    m.addEntries(
      context
          .getSubclassesOf(ApplicationChannel)
          .map((t) => MapEntry(_getClassName(t), ChannelRuntimeImpl(t))),
    );
    m.addEntries(
      context
          .getSubclassesOf(Serializable)
          .map((t) => MapEntry(_getClassName(t), SerializableRuntimeImpl(t))),
    );
    m.addEntries(
      context
          .getSubclassesOf(Controller)
          .map((t) => MapEntry(_getClassName(t), ControllerRuntimeImpl(t))),
    );

    m.addAll(DataModelCompiler().compile(context));

    return m;
  }

  String _getClassName(ClassMirror mirror) {
    return MirrorSystem.getName(mirror.simpleName);
  }
}
