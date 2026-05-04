import 'package:conduit_core/src/runtime/orm/string_case.dart';
import 'package:test/test.dart';

/// Parity fixtures pinning `string_case.dart` to the behavior of the
/// (now-removed) `recase` 4.1.0 package's `ReCase(input).snakeCase` /
/// `input.snakeCase` extension. If any of these change, the ORM's column /
/// table naming will silently drift — bump the schema-migration tests too.
void main() {
  group("snakeCase parity with recase 4.1.0", () {
    final cases = <String, String>{
      // identity-ish: single lowercase word
      "name": "name",
      // camelCase boundary
      "firstName": "first_name",
      "FirstName": "first_name",
      // multi-word camelCase
      "someLongPropertyName": "some_long_property_name",
      // already snake_case
      "first_name": "first_name",
      // all-caps treated as a single word
      "URL": "url",
      "API": "api",
      // mixed separators are dropped
      "first name": "first_name",
      "first-name": "first_name",
      "first.name": "first_name",
      "first/name": "first_name",
      // leading uppercase
      "X": "x",
      // empty string
      "": "",
    };

    cases.forEach((input, expected) {
      test('"$input" -> "$expected"', () {
        expect(input.snakeCase, equals(expected));
      });
    });
  });
}
