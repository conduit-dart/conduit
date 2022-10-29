import 'dart:async';
import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

void main() {
  test("Can add resources to registry that get shut down", () async {
    final controller = StreamController();
    ServiceRegistry.defaultInstance
        .register<StreamController>(controller, (s) => s.close());

    final msgCompleter = Completer();
    controller.stream.listen((msg) {
      msgCompleter.complete();
    });

    controller.add("whatever");
    await msgCompleter.future;

    await ServiceRegistry.defaultInstance.close();
    expect(controller.isClosed, true);
  });

  test("Can remove resource", () async {
    final controller = StreamController();
    ServiceRegistry.defaultInstance
        .register<StreamController>(controller, (s) => s.close());

    final msgCompleter = Completer();
    controller.stream.listen((msg) {
      msgCompleter.complete();
    });

    controller.add("whatever");
    await msgCompleter.future;

    ServiceRegistry.defaultInstance.unregister(controller);

    await ServiceRegistry.defaultInstance.close();
    expect(controller.isClosed, false);

    await controller.close();
  });
}
