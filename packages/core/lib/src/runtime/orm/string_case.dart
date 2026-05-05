/// Tiny in-tree replacement for the (now stale) `recase` package.
///
/// The ORM only ever calls `String.snakeCase`, so we only port that one
/// transform. Behavior is intentionally identical to `recase` 4.1.0's
/// `ReCase(...).snakeCase`:
///
/// - Splits the input on `{' ', '.', '/', '_', '\\', '-'}` (these symbols are
///   dropped, not preserved).
/// - Splits on uppercase boundaries, *unless* the input is entirely uppercase
///   (in which case it is treated as a single word).
/// - Lowercases each word and joins with `_`.
///
/// See `packages/core/test/runtime/string_case_test.dart` for the parity
/// fixtures pinning this behavior to recase's output.
extension StringSnakeCase on String {
  String get snakeCase {
    final words = _groupIntoWords(this);
    return words.map((w) => w.toLowerCase()).join('_');
  }
}

const _symbolSet = {' ', '.', '/', '_', '\\', '-'};
final _upperAlphaRegex = RegExp(r'[A-Z]');

List<String> _groupIntoWords(String text) {
  final buffer = StringBuffer();
  final words = <String>[];
  final isAllCaps = text.toUpperCase() == text;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    final nextChar = i + 1 == text.length ? null : text[i + 1];

    if (_symbolSet.contains(char)) {
      continue;
    }

    buffer.write(char);

    final isEndOfWord = nextChar == null ||
        (_upperAlphaRegex.hasMatch(nextChar) && !isAllCaps) ||
        _symbolSet.contains(nextChar);

    if (isEndOfWord) {
      words.add(buffer.toString());
      buffer.clear();
    }
  }

  return words;
}
