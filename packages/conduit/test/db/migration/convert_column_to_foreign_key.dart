@Timeout(Duration(minutes: 30))
import 'dart:io';

import 'package:test/test.dart';
import '../../../bin/conduit.dart' as c;

void main() {
  /// TODO: migration does not support changing of column types
  test(
    'convert column to foreign key',
    () async {
      Directory.current = '/home/bsutton/git/conduit_support';
      await c.main(['db', 'generate']);
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
