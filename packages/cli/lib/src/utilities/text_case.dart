/// An instance of text to be re-cased.
class TextCase {
  TextCase(String text) : originalText = text {
    _words = _groupIntoWords(text);
  }

  final RegExp _upperAlphaRegex = RegExp('[A-Z]');

  final symbolSet = {' ', '.', '/', '_', '\\', '-'};

  final String originalText;
  late final List<String> _words;

  List<String> _groupIntoWords(String text) {
    final StringBuffer sb = StringBuffer();
    final List<String> words = [];
    final bool isAllCaps = text.toUpperCase() == text;

    for (int i = 0; i < text.length; i++) {
      final String char = text[i];
      final String? nextChar = i + 1 == text.length ? null : text[i + 1];

      if (symbolSet.contains(char)) {
        continue;
      }

      sb.write(char);

      final bool isEndOfWord = nextChar == null ||
          (_upperAlphaRegex.hasMatch(nextChar) && !isAllCaps) ||
          symbolSet.contains(nextChar);

      if (isEndOfWord) {
        words.add(sb.toString());
        sb.clear();
      }
    }

    return words;
  }

  /// snake_case
  String get snakeCase => _getSnakeCase();

  String _getSnakeCase({String separator = '_'}) {
    final List<String> words =
        _words.map((word) => word.toLowerCase()).toList();

    return words.join(separator);
  }
}

extension TextCaseExtension on String {
  String get snakeCase => TextCase(this).snakeCase;
}
