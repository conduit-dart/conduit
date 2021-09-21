import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

abstract class Executable<T extends Object?> {
  Executable(this.message) : _sendPort = message["_sendPort"];

  Future<T> execute();

  final Map<String, dynamic> message;
  final SendPort? _sendPort;

  U instanceOf<U>(
    String typeName, {
    List positionalArguments = const [],
    Map<Symbol, dynamic> namedArguments = const {},
    Symbol constructorName = const Symbol(""),
  }) {
    ClassMirror? typeMirror = currentMirrorSystem()
        .isolate
        .rootLibrary
        .declarations[Symbol(typeName)] as ClassMirror?;

    typeMirror ??= currentMirrorSystem()
        .libraries
        .values
        .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
        .expand((lib) => lib.declarations.values)
        .firstWhere(
          (decl) =>
              decl is ClassMirror &&
              MirrorSystem.getName(decl.simpleName) == typeName,
          orElse: () => throw ArgumentError(
            "Unknown type '$typeName'. Did you forget to import it?",
          ),
        ) as ClassMirror?;

    return typeMirror!
        .newInstance(
          constructorName,
          positionalArguments,
          namedArguments,
        )
        .reflectee as U;
  }

  void send(dynamic message) {
    _sendPort!.send(message);
  }

  void log(String message) {
    _sendPort!.send({"_line_": message});
  }
}
