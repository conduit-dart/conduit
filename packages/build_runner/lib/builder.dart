import 'package:build/build.dart';

import 'package:conduit_build_runner/src/serializable_builder.dart' as s;
import 'package:conduit_build_runner/src/stamp_builder.dart';

Builder stampBuilder(BuilderOptions options) => StampBuilder();

Builder serializableBuilder(BuilderOptions options) =>
    s.serializableBuilder(options);
