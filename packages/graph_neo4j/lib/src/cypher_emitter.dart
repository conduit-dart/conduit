/// Cypher emitter — lowers the dialect-agnostic `GraphPattern` /
/// `GraphQuery` AST shipped by `conduit_graph` (PR #266) into a Cypher
/// string + a parameter map suitable for Bolt's RUN message.
///
/// Design notes
/// ------------
/// - **Parameter binding always.** Filter values are turned into
///   `$pN` parameters in the output Cypher, never interpolated. This
///   sidesteps both injection and serialization concerns (Bolt
///   PackStream natively encodes Dart scalars / lists / maps).
/// - **Stable variable naming.** The anchor uses the user-supplied
///   variable from the pattern; relationships on the anchor get
///   auto-generated `r0`, `r1`, ...; terminal nodes get `m0`, `m1`,
///   ... unless the user pinned a [GraphPatternRelationship.toVariable].
/// - **Filters apply to the anchor only** in v0. The query DSL surfaces
///   property comparisons against the anchor; multi-hop filtering
///   (e.g. constraints on a terminal node) is something a future
///   revision can add by extending the DSL — at which point this
///   emitter grows variable-prefixed property paths.
library;

import 'package:conduit_graph/conduit_graph.dart';

/// The result of lowering a [GraphQuery] (or [GraphPattern]) to
/// Cypher: the query text plus the parameter map to bind on the wire.
class CypherStatement {
  CypherStatement(this.cypher, this.parameters);
  final String cypher;
  final Map<String, Object?> parameters;
  @override
  String toString() => 'CypherStatement($cypher, $parameters)';
}

/// Stateful emitter — accumulates parameter bindings as it walks the
/// AST so each `$pN` placeholder gets a unique key.
class CypherEmitter {
  CypherEmitter();

  final Map<String, Object?> _params = <String, Object?>{};
  int _paramCounter = 0;
  int _hopCounter = 0;

  /// Bind [value] to a fresh parameter name and return the placeholder
  /// (e.g. `\$p0`).
  String _bind(Object? value) {
    final key = 'p${_paramCounter++}';
    _params[key] = value;
    return '\$$key';
  }

  /// Render a bare [GraphPattern] to a `MATCH (...) RETURN <anchor>`
  /// statement. Useful when you don't have a full [GraphQuery] in hand
  /// (e.g. for `traverse`).
  CypherStatement emitPattern(GraphPattern<dynamic> pattern) {
    final match = _renderPattern(pattern);
    final cypher = 'MATCH $match RETURN ${pattern.root.variable}';
    return CypherStatement(cypher, Map.unmodifiable(_params));
  }

  /// Render a full [GraphQuery] — pattern + WHERE + ORDER BY + SKIP /
  /// LIMIT + RETURN.
  CypherStatement emitQuery(GraphQuery<dynamic> query) {
    final match = _renderPattern(query.pattern);
    final buf = StringBuffer('MATCH $match');
    final filter = query.filter;
    if (filter != null) {
      buf.write(' WHERE ');
      buf.write(_renderFilter(filter, query.pattern.root.variable));
    }
    buf.write(' RETURN ${query.pattern.root.variable}');
    if (query.orderBy.isNotEmpty) {
      buf.write(' ORDER BY ');
      buf.write(query.orderBy
          .map(
            (o) =>
                '${query.pattern.root.variable}.${_escapeIdentifier(o.property)} '
                '${o.direction == GraphSortDirection.ascending ? 'ASC' : 'DESC'}',
          )
          .join(', '));
    }
    final offset = query.offset;
    if (offset != null) {
      buf.write(' SKIP ${_bind(offset)}');
    }
    final limit = query.limit;
    if (limit != null) {
      buf.write(' LIMIT ${_bind(limit)}');
    }
    return CypherStatement(buf.toString(), Map.unmodifiable(_params));
  }

  /// Render a standalone [GraphFilterExpression]. Exposed for tests
  /// and for callers that already have the rest of a query but want a
  /// WHERE fragment in isolation.
  String emitFilter(GraphFilterExpression filter, {String anchor = 'n'}) {
    return _renderFilter(filter, anchor);
  }

  /// Snapshot of parameters bound so far. Useful when callers want to
  /// emit several fragments and then submit them all together.
  Map<String, Object?> get parameters => Map.unmodifiable(_params);

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  String _renderPattern(GraphPattern<dynamic> pattern) {
    final root = pattern.root;
    final buf = StringBuffer()..write(_renderNodeStep(root.variable, root.label));
    for (final hop in root.relationships) {
      _hopCounter++;
      final relVar = 'r${_hopCounter - 1}';
      final toVar = hop.toVariable ?? 'm${_hopCounter - 1}';
      final arrowOpen = _arrowOpen(hop.direction);
      final arrowClose = _arrowClose(hop.direction);
      buf
        ..write(arrowOpen)
        ..write('[$relVar:${_escapeIdentifier(hop.edgeLabel.name)}]')
        ..write(arrowClose)
        ..write(_renderNodeStep(toVar, hop.toLabel));
    }
    return buf.toString();
  }

  String _renderNodeStep(String variable, GraphLabel? label) {
    if (label == null) {
      return '($variable)';
    }
    return '($variable:${_escapeIdentifier(label.name)})';
  }

  String _arrowOpen(GraphRelationshipDirection d) {
    switch (d) {
      case GraphRelationshipDirection.outgoing:
        return '-';
      case GraphRelationshipDirection.incoming:
        return '<-';
      case GraphRelationshipDirection.undirected:
        return '-';
    }
  }

  String _arrowClose(GraphRelationshipDirection d) {
    switch (d) {
      case GraphRelationshipDirection.outgoing:
        return '->';
      case GraphRelationshipDirection.incoming:
        return '-';
      case GraphRelationshipDirection.undirected:
        return '-';
    }
  }

  String _renderFilter(GraphFilterExpression f, String anchor) {
    if (f is GraphPropertyFilter) {
      return _renderProperty(f, anchor);
    }
    if (f is GraphCompoundFilter) {
      final op = f.combinator == GraphFilterCombinator.and ? 'AND' : 'OR';
      return '(${f.children.map((c) => _renderFilter(c, anchor)).join(' $op ')})';
    }
    if (f is GraphNotFilter) {
      return 'NOT (${_renderFilter(f.child, anchor)})';
    }
    throw ArgumentError(
      'Unrecognized GraphFilterExpression subtype: ${f.runtimeType}',
    );
  }

  String _renderProperty(GraphPropertyFilter f, String anchor) {
    final lhs = '$anchor.${_escapeIdentifier(f.property)}';
    switch (f.operator) {
      case GraphFilterOperator.equal:
        return '$lhs = ${_bind(f.value)}';
      case GraphFilterOperator.notEqual:
        return '$lhs <> ${_bind(f.value)}';
      case GraphFilterOperator.greaterThan:
        return '$lhs > ${_bind(f.value)}';
      case GraphFilterOperator.greaterThanOrEqual:
        return '$lhs >= ${_bind(f.value)}';
      case GraphFilterOperator.lessThan:
        return '$lhs < ${_bind(f.value)}';
      case GraphFilterOperator.lessThanOrEqual:
        return '$lhs <= ${_bind(f.value)}';
      case GraphFilterOperator.contains:
        return '$lhs CONTAINS ${_bind(f.value)}';
      case GraphFilterOperator.startsWith:
        return '$lhs STARTS WITH ${_bind(f.value)}';
      case GraphFilterOperator.endsWith:
        return '$lhs ENDS WITH ${_bind(f.value)}';
      case GraphFilterOperator.inList:
        return '$lhs IN ${_bind(f.value)}';
      case GraphFilterOperator.isNull:
        return '$lhs IS NULL';
      case GraphFilterOperator.isNotNull:
        return '$lhs IS NOT NULL';
    }
  }

  /// Escape an identifier (label name, property name) for Cypher.
  ///
  /// We backtick-quote any identifier that contains a non-alphanumeric
  /// character so labels with spaces / dashes / leading digits round-
  /// trip safely. Plain `[A-Za-z_][A-Za-z0-9_]*` identifiers are
  /// emitted bare for readability.
  static final _safeIdent = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  String _escapeIdentifier(String s) {
    if (_safeIdent.hasMatch(s)) return s;
    final escaped = s.replaceAll('`', '``');
    return '`$escaped`';
  }
}

/// Convenience: lower [pattern] in a fresh emitter.
CypherStatement emitPattern(GraphPattern<dynamic> pattern) =>
    CypherEmitter().emitPattern(pattern);

/// Convenience: lower [query] in a fresh emitter.
CypherStatement emitQuery(GraphQuery<dynamic> query) =>
    CypherEmitter().emitQuery(query);
