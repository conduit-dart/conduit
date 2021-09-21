import 'dart:convert';

import 'package:conduit_password_hash/conduit_password_hash.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

List<int> encodeBytes(String bytes) {
  final byteList = bytes.split(" ");
  final result = <int>[];
  for (final byte in byteList) {
    result.add(int.parse(byte, radix: 16));
  }
  return result;
}

void main() {
  group("Salt", () {
    test("Can generate random list of integers", () {
      final salt = Salt.generate(64);
      expect(salt.length, 64);

      expect(salt, everyElement(lessThan(256)));
      expect(salt, everyElement(greaterThanOrEqualTo(0)));
    });

    test("Can generate base64 salt", () {
      final salt = Salt.generateAsBase64String(64);
      expect(salt is String, true);

      final decoded = const Base64Decoder().convert(salt);
      expect(decoded.length, 64);

      expect(decoded, everyElement(lessThan(256)));
      expect(decoded, everyElement(greaterThanOrEqualTo(0)));
    });
  });

  group("RFC6070", () {
    test("Disallow large values of derived key length", () {
      final sha = sha1;
      final hLen = sha.blockSize;
      final gen = PBKDF2(hashAlgorithm: sha);

      try {
        gen.generateKey("password", "salt", 1, ((2 << 31) - 1) * hLen + 1);
        expect(true, false);
      } on PBKDF2Exception catch (e) {
        expect(e.toString(), contains("Derived key too long"));
      }
    });

    test("Test vectors 1", () {
      final gen = PBKDF2(hashAlgorithm: sha1);
      final output = gen.generateKey("password", "salt", 1, 20);
      expect(
        output,
        encodeBytes(
          "0c 60 c8 0f 96 1f 0e 71 f3 a9 b5 24 af 60 12 06 2f e0 37 a6",
        ),
      );
    });

    test("Test vectors 2", () {
      final gen = PBKDF2(hashAlgorithm: sha1);
      final output = gen.generateKey("password", "salt", 2, 20);
      expect(
        output,
        encodeBytes(
          "ea 6c 01 4d c7 2d 6f 8c cd 1e d9 2a ce 1d 41 f0 d8 de 89 57",
        ),
      );
    });

    test("Test vectors 3", () {
      final gen = PBKDF2(hashAlgorithm: sha1);
      final output = gen.generateKey("password", "salt", 4096, 20);
      expect(
        output,
        encodeBytes(
          "4b 00 79 01 b7 65 48 9a be ad 49 d9 26 f7 21 d0 65 a4 29 c1",
        ),
      );
    });

    // This test may take a few minutes to run
    test("Test vectors 4", () {
      final gen = PBKDF2(hashAlgorithm: sha1);
      final output = gen.generateKey("password", "salt", 16777216, 20);
      expect(
        output,
        encodeBytes(
          "ee fe 3d 61 cd 4d a4 e4 e9 94 5b 3d 6b a2 15 8c 26 34 e9 84",
        ),
      );
    });

    test("Test vectors 5", () {
      final gen = PBKDF2(hashAlgorithm: sha1);
      final output = gen.generateKey(
        "passwordPASSWORDpassword",
        "saltSALTsaltSALTsaltSALTsaltSALTsalt",
        4096,
        25,
      );
      expect(
        output,
        encodeBytes(
          "3d 2e ec 4f e4 1c 84 9b 80 c8 d8 36 62 c0 e4 4a 8b 29 1a 96 4c f2 f0 70 38",
        ),
      );
    });

    test("Test vectors 6", () {
      final gen = PBKDF2(hashAlgorithm: sha1);
      final output = gen.generateKey("pass\u0000word", "sa\u0000lt", 4096, 16);
      expect(
        output,
        encodeBytes("56 fa 6a a7 55 48 09 9d cc 37 d7 f0 34 25 e0 c3"),
      );
    });
  });

  group("Sha256", () {
    test("Disallow large values of derived key length", () {
      final sha = sha256;
      final hLen = sha.blockSize;
      final gen = PBKDF2(hashAlgorithm: sha);

      try {
        gen.generateKey("password", "salt", 1, ((2 << 31) - 1) * hLen + 1);
        expect(true, false);
      } on PBKDF2Exception catch (e) {
        expect(e.toString(), contains("Derived key too long"));
      }
    });

    test("Test vectors 1", () {
      final gen = PBKDF2(hashAlgorithm: sha256);
      final output = gen.generateKey("password", "salt", 1, 32);
      expect(
        output,
        encodeBytes(
          "12 0f b6 cf fc f8 b3 2c 43 e7 22 52 56 c4 f8 37 a8 65 48 c9 2c cc 35 48 08 05 98 7c b7 0b e1 7b",
        ),
      );
    });

    test("Test vectors 2", () {
      final gen = PBKDF2(hashAlgorithm: sha256);
      final output = gen.generateKey("password", "salt", 2, 32);
      expect(
        output,
        encodeBytes(
          "ae 4d 0c 95 af 6b 46 d3 2d 0a df f9 28 f0 6d d0 2a 30 3f 8e f3 c2 51 df d6 e2 d8 5a 95 47 4c 43",
        ),
      );
    });

    test("Test vectors 3", () {
      final gen = PBKDF2(hashAlgorithm: sha256);
      final output = gen.generateKey("password", "salt", 4096, 32);
      expect(
        output,
        encodeBytes(
          "c5 e4 78 d5 92 88 c8 41 aa 53 0d b6 84 5c 4c 8d 96 28 93 a0 01 ce 4e 11 a4 96 38 73 aa 98 13 4a",
        ),
      );
    });

    // This test may take a few minutes to run
    test("Test vectors 4", () {
      final gen = PBKDF2(hashAlgorithm: sha256);
      final output = gen.generateKey("password", "salt", 16777216, 32);
      expect(
        output,
        encodeBytes(
          "cf 81 c6 6f e8 cf c0 4d 1f 31 ec b6 5d ab 40 89 f7 f1 79 e8 9b 3b 0b cb 17 ad 10 e3 ac 6e ba 46",
        ),
      );
    });

    test("Test vectors 5", () {
      final gen = PBKDF2(hashAlgorithm: sha256);
      final output = gen.generateKey(
        "passwordPASSWORDpassword",
        "saltSALTsaltSALTsaltSALTsaltSALTsalt",
        4096,
        40,
      );
      expect(
        output,
        encodeBytes(
          "34 8c 89 db cb d3 2b 2f 32 d8 14 b8 11 6e 84 cf 2b 17 34 7e bc 18 00 18 1c 4e 2a 1f b8 dd 53 e1 c6 35 51 8c 7d ac 47 e9",
        ),
      );
    });

    test("Test vectors 6", () {
      final gen = PBKDF2(hashAlgorithm: sha256);
      final output = gen.generateKey("pass\u0000word", "sa\u0000lt", 4096, 16);
      expect(
        output,
        encodeBytes("89 b6 9d 05 16 f8 29 89 3c 69 62 26 65 0a 86 87"),
      );
    });
  });
}
