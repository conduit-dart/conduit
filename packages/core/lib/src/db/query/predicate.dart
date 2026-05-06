import 'package:conduit_core/src/db/persistent_store/persistent_store.dart';
import 'package:conduit_core/src/db/query/expression_ast.dart';
import 'package:conduit_core/src/db/query/query.dart';

/// A predicate contains instructions for filtering rows when performing a [Query].
///
/// Predicates currently are the WHERE clause in a SQL statement and are used verbatim
/// by the [PersistentStore]. In general, you should use [Query.where] instead of using this class directly, as [Query.where] will
/// use the underlying [PersistentStore] to generate a [QueryPredicate] for you.
///
/// A predicate has a format and parameters. The format is the [String] that comes after WHERE in a SQL query. The format may
/// have parameterized values, for which the corresponding value is in the [parameters] map. A parameter is prefixed with '@' in the format string. Currently,
/// the format string's parameter syntax is defined by the [PersistentStore] it is used on. An example of that format:
///
///     var predicate = new QueryPredicate("x = @xValue", {"xValue" : 5});
///
/// In addition to the legacy raw-string surface, predicates may now also
/// carry a dialect-neutral [expression] AST (see `expression_ast.dart`).
/// When a backend recognizes the AST it renders dialect-correct SQL +
/// bindings from it; otherwise the [format] / [parameters] surface is
/// used verbatim. Predicates produced by Conduit's internal builders
/// populate both forms — the [format] field stays a Postgres-flavored
/// string for back-compat with code that consumes it directly.
class QueryPredicate {
  /// Default constructor
  ///
  /// The [format] and [parameters] of this predicate. [parameters] may be null.
  /// An [expression] AST may also be supplied; backends that understand
  /// the AST render from it instead of the raw format string.
  QueryPredicate(this.format, [this.parameters = const {}, this.expression]);

  /// Creates an empty predicate.
  ///
  /// The format string is the empty string and parameters is the empty map.
  QueryPredicate.empty()
      : format = "",
        parameters = {},
        expression = null;

  /// Creates a predicate with an attached [expression] AST and a
  /// pre-rendered [format] / [parameters] pair (the named-parameter
  /// rendering of that AST). Both halves are kept so legacy consumers
  /// of `predicate.format` keep working byte-for-byte while AST-aware
  /// dialects can render the predicate in their preferred placeholder
  /// style.
  QueryPredicate.withExpression(
    this.expression,
    this.format,
    this.parameters,
  );

  /// Combines [predicates] with 'AND' keyword.
  ///
  /// The [format] of the return value is produced by joining together each [predicates]
  /// [format] string with 'AND'. Each [parameters] from individual [predicates] is combined
  /// into the returned [parameters].
  ///
  /// If there are duplicate parameter names in [predicates], they will be disambiguated by suffixing
  /// the parameter name in both [format] and [parameters] with a unique integer.
  ///
  /// If [predicates] is null or empty, an empty predicate is returned. If [predicates] contains only
  /// one predicate, that predicate is returned.
  factory QueryPredicate.and(Iterable<QueryPredicate> predicates) {
    final predicateList = predicates.where((p) => p.format.isNotEmpty).toList();

    if (predicateList.isEmpty) {
      return QueryPredicate.empty();
    }

    if (predicateList.length == 1) {
      return predicateList.first;
    }

    // Collect AST nodes from constituent predicates so AST-aware
    // dialects can render the combined predicate from a fresh
    // `LogicalExpression(AND, ...)` rather than re-parsing the
    // string.
    //
    // Two correctness conditions before we propagate the AST:
    //   (1) every constituent has an `expression` AST — partial AST
    //       coverage would silently corrupt positional-parameter
    //       renders by missing some values.
    //   (2) no parameter-name collision occurred (the dupe-renaming
    //       below only rewrites the format string + map, not the
    //       AST). If either condition fails we drop the AST and the
    //       backend falls back to rendering from the format string.
    final childExpressions = <SqlExpression>[];
    bool allHaveExpressions = true;
    for (final p in predicateList) {
      final expr = p.expression;
      if (expr == null) {
        allHaveExpressions = false;
        break;
      }
      childExpressions.add(expr);
    }

    // If we have duplicate keys anywhere, we need to disambiguate them.
    int dupeCounter = 0;
    bool dupeOccurred = false;
    final allFormatStrings = [];
    final valueMap = <String, dynamic>{};
    for (final predicate in predicateList) {
      final duplicateKeys = predicate.parameters.keys
          .where((k) => valueMap.keys.contains(k))
          .toList();

      if (duplicateKeys.isNotEmpty) {
        dupeOccurred = true;
        var fmt = predicate.format;
        final Map<String, String> dupeMap = {};
        for (final key in duplicateKeys) {
          final replacementKey = "$key$dupeCounter";
          fmt = fmt.replaceAll("@$key", "@$replacementKey");
          dupeMap[key] = replacementKey;
          dupeCounter++;
        }

        allFormatStrings.add(fmt);
        predicate.parameters.forEach((key, value) {
          valueMap[dupeMap[key] ?? key] = value;
        });
      } else {
        allFormatStrings.add(predicate.format);
        valueMap.addAll(predicate.parameters);
      }
    }

    final predicateFormat = "(${allFormatStrings.join(" AND ")})";
    final combinedExpression = (allHaveExpressions && !dupeOccurred)
        ? LogicalExpression('AND', childExpressions)
        : null;
    return QueryPredicate(predicateFormat, valueMap, combinedExpression);
  }

  /// The string format of the this predicate.
  ///
  /// This is the predicate text. Do not write dynamic values directly to the format string, instead, prefix an identifier with @
  /// and add that identifier to the [parameters] map.
  String format;

  /// A map of values to replace in the format string at execution time.
  ///
  /// Input values should not be in the format string, but instead provided in this map.
  /// Keys of this map will be searched for in the format string and be replaced by the value in this map.
  Map<String, dynamic> parameters;

  /// Optional dialect-neutral predicate AST. When non-null, AST-aware
  /// backends render this in preference to [format] — the same logical
  /// expression, but with placeholders, identifier quoting, and
  /// operator spelling chosen by the backend's `SqlDialect`.
  ///
  /// `null` for predicates constructed via the legacy string
  /// constructor (e.g., user-written `QueryPredicate("x = @xValue",
  /// {...})`); those still flow through the `format`-string path.
  SqlExpression? expression;
}

/// The operator in a comparison matcher.
enum PredicateOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}

class ComparisonExpression implements PredicateExpression {
  const ComparisonExpression(this.value, this.operator);

  final dynamic value;
  final PredicateOperator operator;

  @override
  PredicateExpression get inverse {
    return ComparisonExpression(value, inverseOperator);
  }

  PredicateOperator get inverseOperator {
    switch (operator) {
      case PredicateOperator.lessThan:
        return PredicateOperator.greaterThanEqualTo;
      case PredicateOperator.greaterThan:
        return PredicateOperator.lessThanEqualTo;
      case PredicateOperator.notEqual:
        return PredicateOperator.equalTo;
      case PredicateOperator.lessThanEqualTo:
        return PredicateOperator.greaterThan;
      case PredicateOperator.greaterThanEqualTo:
        return PredicateOperator.lessThan;
      case PredicateOperator.equalTo:
        return PredicateOperator.notEqual;
    }
  }
}

/// The operator in a string matcher.
enum PredicateStringOperator { beginsWith, contains, endsWith, equals }

abstract class PredicateExpression {
  PredicateExpression get inverse;
}

class RangeExpression implements PredicateExpression {
  const RangeExpression(this.lhs, this.rhs, {this.within = true});

  final bool within;
  final dynamic lhs;
  final dynamic rhs;

  @override
  PredicateExpression get inverse {
    return RangeExpression(lhs, rhs, within: !within);
  }
}

class NullCheckExpression implements PredicateExpression {
  const NullCheckExpression({this.shouldBeNull = true});

  final bool shouldBeNull;

  @override
  PredicateExpression get inverse {
    return NullCheckExpression(shouldBeNull: !shouldBeNull);
  }
}

class SetMembershipExpression implements PredicateExpression {
  const SetMembershipExpression(this.values, {this.within = true});

  final List<dynamic> values;
  final bool within;

  @override
  PredicateExpression get inverse {
    return SetMembershipExpression(values, within: !within);
  }
}

class StringExpression implements PredicateExpression {
  const StringExpression(
    this.value,
    this.operator, {
    this.caseSensitive = true,
    this.invertOperator = false,
    this.allowSpecialCharacters = true,
  });

  final PredicateStringOperator operator;
  final bool invertOperator;
  final bool caseSensitive;
  final bool allowSpecialCharacters;
  final String value;

  @override
  PredicateExpression get inverse {
    return StringExpression(
      value,
      operator,
      caseSensitive: caseSensitive,
      invertOperator: !invertOperator,
      allowSpecialCharacters: allowSpecialCharacters,
    );
  }
}
