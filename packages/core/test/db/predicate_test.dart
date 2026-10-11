import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  group("QueryPredicate.and", () {
    test("Duplicate keys are replaced", () {
      final p1 = QueryPredicate("p=@p", {"p": 1});
      final p2 = QueryPredicate("p=@p", {"p": 2});
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.format, "(p=@p AND p=@p_0)");
      expect(combined.parameters, {"p": 1, "p_0": 2});
    });

    test("Multiple duplicate keys are replaced", () {
      final p1 = QueryPredicate("p=@p", {"p": 1});
      final p2 = QueryPredicate("p=@p", {"p": 2});
      final p3 = QueryPredicate("p=@p", {"p": 3});
      final combined = QueryPredicate.and([p1, p2, p3]);
      expect(combined.format, "(p=@p AND p=@p_0 AND p=@p_1)");
      expect(combined.parameters, {"p": 1, "p_0": 2, "p_1": 3});
    });

    test("Duplicate keys in :name placeholders are replaced", () {
      final p1 = QueryPredicate("n<:n", {"n": 1});
      final p2 = QueryPredicate("n>:n", {"n": 2});
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.format, "(n<:n AND n>:n_0)");
      expect(combined.parameters, {"n": 1, "n_0": 2});
    });

    test("Rename does not touch longer names sharing the prefix", () {
      final p1 = QueryPredicate("n=@n", {"n": 1});
      final p2 = QueryPredicate("n=@n AND m=@n_other", {"n": 2, "n_other": 3});
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.format, "(n=@n AND n=@n_0 AND m=@n_other)");
      expect(combined.parameters, {"n": 1, "n_0": 2, "n_other": 3});
    });

    test("Rename does not touch :: casts", () {
      final p1 = QueryPredicate("n=@n", {"n": 1});
      final p2 = QueryPredicate("n=@n AND x::n IS NULL", {"n": 2});
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.format, "(n=@n AND n=@n_0 AND x::n IS NULL)");
    });

    test("Replacement key avoids existing keys", () {
      final p1 = QueryPredicate("n=@n", {"n": 1});
      final p2 = QueryPredicate("n=@n AND m=@n_0", {"n": 2, "n_0": 3});
      final combined = QueryPredicate.and([p1, p2]);
      expect(combined.format, "(n=@n AND n=@n_1 AND m=@n_0)");
      expect(combined.parameters, {"n": 1, "n_1": 2, "n_0": 3});
    });

    test("AST is retained when keys are duplicated", () {
      const e1 = BinaryOpExpression(
        '<',
        ColumnExpression('n'),
        ParameterExpression('n', 1),
      );
      const e2 = BinaryOpExpression(
        '>',
        ColumnExpression('n'),
        ParameterExpression('n', 2),
      );
      final combined = QueryPredicate.and([
        QueryPredicate.withExpression(e1, "n<@n", {"n": 1}),
        QueryPredicate.withExpression(e2, "n>@n", {"n": 2}),
      ]);
      expect(combined.expression, isA<LogicalExpression>());
      expect(combined.format, "(n<@n AND n>@n_0)");
    });

    test("AST is dropped when any predicate lacks one", () {
      const e1 = BinaryOpExpression(
        '<',
        ColumnExpression('n'),
        ParameterExpression('n', 1),
      );
      final combined = QueryPredicate.and([
        QueryPredicate.withExpression(e1, "n<@n", {"n": 1}),
        QueryPredicate("n>@n", {"n": 2}),
      ]);
      expect(combined.expression, isNull);
      expect(combined.format, "(n<@n AND n>@n_0)");
    });

    test("If empty list, return empty predicate", () {
      expect(QueryPredicate.and([]).format, "");
      expect(QueryPredicate.and([]).parameters, {});
    });

    // No Longer allowing null values
    // test("If null, return empty predicate", () {
    //   expect(QueryPredicate.and(null).format, "");
    //   expect(QueryPredicate.and(null).parameters, {});
    // });

    test("If only one element in list, return that element", () {
      final valid = QueryPredicate("x=@a", {"a": 0});
      final p = QueryPredicate.and([valid]);
      expect(p.format, valid.format);
      expect(p.parameters, valid.parameters);
    });

    test("If and'ing empty predicate, ignore it", () {
      final valid = QueryPredicate("x=@a", {"a": 0});
      final p = QueryPredicate.and([valid, QueryPredicate.empty()]);
      expect(p.format, valid.format);
      expect(p.parameters, valid.parameters);
    });

    // Not allowing null values
    // test("If and'ing null predicate, ignore it", () {
    //   final valid = QueryPredicate("x=@a", {"a": 0});
    //   final p = QueryPredicate.and([valid, null]);
    //   expect(p.format, valid.format);
    //   expect(p.parameters, valid.parameters);
    // });

    test("And'ing predicate with no parameters", () {
      final valid = QueryPredicate("x=y");
      final p = QueryPredicate.and([valid]);
      expect(p.format, valid.format);
      expect(p.parameters, {});
    });
  });
}
