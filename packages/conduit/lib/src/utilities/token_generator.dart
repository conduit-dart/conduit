import 'dart:math';

String randomStringOfLength(int length) {
  const possibleCharacters =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  final buff = StringBuffer();

  final r = Random.secure();
  for (int i = 0; i < length; i++) {
    buff.write(
        "${possibleCharacters[r.nextInt(1000) % possibleCharacters.length]}");
  }

  return buff.toString();
}
