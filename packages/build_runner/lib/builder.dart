import 'package:build/build.dart';

import 'package:conduit_build_runner/src/channel_builder.dart' as c;
import 'package:conduit_build_runner/src/configuration_builder.dart' as cfg;
import 'package:conduit_build_runner/src/controller_builder.dart' as ctl;
import 'package:conduit_build_runner/src/managed_object_builder.dart' as m;
import 'package:conduit_build_runner/src/registry_builder.dart' as r;
import 'package:conduit_build_runner/src/serializable_builder.dart' as s;
import 'package:conduit_build_runner/src/stamp_builder.dart';

Builder stampBuilder(BuilderOptions options) => StampBuilder();

Builder channelBuilder(BuilderOptions options) => c.channelBuilder(options);

Builder configurationBuilder(BuilderOptions options) =>
    cfg.configurationBuilder(options);

Builder controllerBuilder(BuilderOptions options) =>
    ctl.controllerBuilder(options);

Builder managedObjectBuilder(BuilderOptions options) =>
    m.managedObjectBuilder(options);

Builder serializableBuilder(BuilderOptions options) =>
    s.serializableBuilder(options);

Builder registryBuilder(BuilderOptions options) => r.RegistryBuilder();
