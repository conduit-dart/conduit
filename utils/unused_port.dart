import 'package:test_core/src/util/io.dart';

void main() async {
  print(await getUnusedPort((port) => port));
}
