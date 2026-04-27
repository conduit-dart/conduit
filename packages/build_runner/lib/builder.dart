import 'package:build/build.dart';

import 'package:conduit_build_runner/src/channel_builder.dart' as c;
import 'package:conduit_build_runner/src/registry_builder.dart' as r;
import 'package:conduit_build_runner/src/serializable_builder.dart' as s;
import 'package:conduit_build_runner/src/stamp_builder.dart';

Builder stampBuilder(BuilderOptions options) => StampBuilder();

Builder channelBuilder(BuilderOptions options) => c.channelBuilder(options);

Builder serializableBuilder(BuilderOptions options) =>
    s.serializableBuilder(options);

Builder registryBuilder(BuilderOptions options) => r.RegistryBuilder();
