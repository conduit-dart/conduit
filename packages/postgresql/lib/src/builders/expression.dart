import 'package:postgres/postgres.dart';

import 'column.dart';
import 'table.dart';
import 'package:conduit_core/conduit_core.dart';

class ColumnExpressionBuilder extends ColumnBuilder {
  ColumnExpressionBuilder(
    TableBuilder super.table,
    super.property,
    this.expression, {
    this.prefix = "",
  });

  final String prefix;
  PredicateExpression? expression;

  String get defaultPrefix => "$prefix${table!.sqlTableReference}_";

  QueryPredicate get predicate {
    final expr = expression;
    if (expr is ComparisonExpression) {
      return comparisonPredicate(expr.operator, expr.value);
    } else if (expr is RangeExpression) {
      return rangePredicate(expr.lhs, expr.rhs, insideRange: expr.within);
    } else if (expr is NullCheckExpression) {
      return nullPredicate(isNull: expr.shouldBeNull);
    } else if (expr is SetMembershipExpression) {
      return containsPredicate(expr.values, within: expr.within);
    } else if (expr is StringExpression) {
      return stringPredicate(
        expr.operator,
        expr.value,
        caseSensitive: expr.caseSensitive,
        invertOperator: expr.invertOperator,
        allowSpecialCharacters: expr.allowSpecialCharacters,
      );
    }

    throw UnsupportedError(
      "Unknown expression applied to 'Query'. '${expr.runtimeType}' is not supported by 'PostgreSQL'.",
    );
  }

  /// Convenience access to the dialect threaded through the table builder.
  SqlDialect get _dialect => table!.dialect;

  /// Build a postgres-typed value wrapper for [v]; centralized so the
  /// AST nodes carry the same `TypedValue` the legacy path put in the
  /// parameter map. Keeps PG behavior identical pre- and post-AST.
  TypedValue _typed(Object? v) =>
      TypedValue(ColumnBuilder.typeMap[property!.type!.kind]!,
          convertValueForStorage(v));

  /// `column` AST node for the predicate's left-hand side. The PG
  /// renderer always namespaces with the table reference (matches
  /// the historical `withTableNamespace: true` call site).
  ColumnExpression _columnNode() {
    final raw = sqlColumnName();
    return ColumnExpression(
      raw,
      tableNamespace: table!.sqlTableReference,
    );
  }

  QueryPredicate comparisonPredicate(
    PredicateOperator? operator,
    dynamic value,
  ) {
    final name = sqlColumnName(withTableNamespace: true);
    final variableName = sqlColumnName(withPrefix: defaultPrefix);
    final op = ColumnBuilder.symbolTable[operator!]!;
    final typed = _typed(value);

    final ast = BinaryOpExpression(
      op,
      _columnNode(),
      ParameterExpression(variableName, typed),
    );

    return QueryPredicate.withExpression(
      ast,
      "$name $op ${_dialect.parameterPlaceholder(variableName)}",
      {variableName: typed},
    );
  }

  QueryPredicate containsPredicate(
    Iterable<dynamic> values, {
    bool within = true,
  }) {
    final tokenList = [];
    final pairedMap = <String, TypedValue>{};
    final astValues = <SqlExpression>[];

    var counter = 0;
    for (final value in values) {
      final prefix = "$defaultPrefix${counter}_";

      final variableName = sqlColumnName(withPrefix: prefix);
      tokenList.add(_dialect.parameterPlaceholder(variableName));
      final typed = _typed(value);
      pairedMap[variableName] = typed;
      astValues.add(ParameterExpression(variableName, typed));

      counter++;
    }

    final name = sqlColumnName(withTableNamespace: true);
    final keyword = within ? "IN" : "NOT IN";
    final ast = InExpression(_columnNode(), astValues, negated: !within);
    return QueryPredicate.withExpression(
      ast,
      "$name $keyword (${tokenList.join(",")})",
      pairedMap,
    );
  }

  QueryPredicate nullPredicate({bool isNull = true}) {
    final name = sqlColumnName(withTableNamespace: true);
    final op = isNull ? _dialect.isNullOperator : _dialect.isNotNullOperator;
    final ast = IsNullExpression(_columnNode(), negated: !isNull);
    return QueryPredicate.withExpression(ast, "$name $op", {});
  }

  QueryPredicate rangePredicate(
    dynamic lhsValue,
    dynamic rhsValue, {
    bool insideRange = true,
  }) {
    final name = sqlColumnName(withTableNamespace: true);
    final lhsName = sqlColumnName(withPrefix: "${defaultPrefix}lhs_");
    final rhsName = sqlColumnName(withPrefix: "${defaultPrefix}rhs_");
    final operation = insideRange ? "BETWEEN" : "NOT BETWEEN";
    final lhsTyped = _typed(lhsValue);
    final rhsTyped = _typed(rhsValue);

    final ast = BetweenExpression(
      _columnNode(),
      ParameterExpression(lhsName, lhsTyped),
      ParameterExpression(rhsName, rhsTyped),
      negated: !insideRange,
    );

    return QueryPredicate.withExpression(
      ast,
      "$name $operation ${_dialect.parameterPlaceholder(lhsName)} "
      "AND ${_dialect.parameterPlaceholder(rhsName)}",
      {lhsName: lhsTyped, rhsName: rhsTyped},
    );
  }

  QueryPredicate stringPredicate(
    PredicateStringOperator operator,
    String value, {
    bool caseSensitive = true,
    bool invertOperator = false,
    bool allowSpecialCharacters = true,
  }) {
    final n = sqlColumnName(withTableNamespace: true);
    final variableName = sqlColumnName(withPrefix: defaultPrefix);

    var matchValue =
        allowSpecialCharacters ? value : _dialect.escapeLikePattern(value);

    var operation = caseSensitive
        ? _dialect.caseSensitiveLikeOperator
        : _dialect.caseInsensitiveLikeOperator;
    if (invertOperator) {
      operation = "NOT $operation";
    }
    switch (operator) {
      case PredicateStringOperator.beginsWith:
        matchValue = "$matchValue%";
        break;
      case PredicateStringOperator.endsWith:
        matchValue = "%$matchValue";
        break;
      case PredicateStringOperator.contains:
        matchValue = "%$matchValue%";
        break;
      default:
        break;
    }

    final typed = TypedValue(Type.text, matchValue);
    final ast = LikeExpression(
      _columnNode(),
      ParameterExpression(variableName, typed),
      caseSensitive: caseSensitive,
      negated: invertOperator,
    );

    return QueryPredicate.withExpression(
      ast,
      "$n $operation ${_dialect.parameterPlaceholder(variableName)}",
      {variableName: typed},
    );
  }
}
