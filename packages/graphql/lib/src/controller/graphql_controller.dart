import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:graphql_parser2/graphql_parser2.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';

import '../resolvers/data_loader.dart';
import '../resolvers/sql_resolver_factory.dart' show dataLoaderRegistryArgKey;

/// GraphQL request / response key constants per the
/// [GraphQL-over-HTTP spec](https://graphql.github.io/graphql-over-http/draft/).
const _kQuery = 'query';
const _kOperationName = 'operationName';
const _kVariables = 'variables';
// `extensions` is accepted on input but otherwise ignored in G1.
const _kExtensions = 'extensions';

/// The `application/graphql` content type — historical Apollo / Express
/// convention where the request body is a raw GraphQL document with no
/// JSON envelope. The current spec keeps it as an optional input form,
/// and we accept it for compatibility.
final _applicationGraphQL = ContentType('application', 'graphql');

/// The standard, mandatory output content type.
final _applicationJson = ContentType.json;

/// The newer GraphQL-over-HTTP response media type. We answer `Accept:
/// application/graphql-response+json` with this exact content type so
/// negotiating clients see the spec-aligned envelope.
final _applicationGraphQLResponseJson =
    ContentType('application', 'graphql-response+json');

/// Registers the `application/graphql-response+json` codec with
/// Conduit's [CodecRegistry] exactly once. The spec defines this media
/// type as JSON; we route it through the existing JSON codec so
/// negotiating clients receive the spec-aligned envelope without
/// callers having to register anything in their `ApplicationChannel`.
bool _codecRegistered = false;
void _ensureCodecRegistered() {
  if (_codecRegistered) return;
  CodecRegistry.defaultInstance.add(
    ContentType('application', 'graphql-response+json', charset: 'utf-8'),
    const JsonCodec(),
  );
  _codecRegistered = true;
}

/// HTTP transport for GraphQL.
///
/// Mount one of these on a route to expose a GraphQL endpoint backed by
/// a hand-written [GraphQLSchema]. Implements the
/// [GraphQL-over-HTTP spec](https://graphql.github.io/graphql-over-http/draft/)
/// for the `POST` (queries + mutations) and `GET` (queries only) methods.
///
/// **G1 scope.** The schema is hand-assembled by the caller. Schema
/// derivation from `ManagedDataModel` is deferred to G2; a resolver
/// framework that integrates with `Query<T>` / `GraphQuery` is deferred
/// to G3 / G4; field-level auth and cross-source dispatch is deferred
/// to G5; subscriptions are out of scope for the entire plan.
///
/// ### Wire format
///
/// **Request body (POST, `application/json`).**
///
/// ```json
/// {
///   "query":         "<GraphQL document>",
///   "operationName": "<optional>",
///   "variables":     { "<name>": <value>, ... },
///   "extensions":    { ... }   // accepted but ignored in G1
/// }
/// ```
///
/// **Request body (POST, `application/graphql`).** The full body is the
/// query document; no JSON envelope.
///
/// **GET querystring.** `?query=...&operationName=...&variables=<JSON>`.
/// Per the spec, GET is restricted to `query` operations — mutations
/// receive HTTP 405.
///
/// **Response.** Always JSON, shape:
///
/// ```json
/// { "data": ..., "errors": [ { "message": ..., "locations": [...], "path": [...], "extensions": {...} } ] }
/// ```
///
/// Per the spec:
///   * Parse / validate / variable-coercion failures are HTTP 400 with
///     no `data` key.
///   * Field-resolver / runtime errors are HTTP 200 with `errors[]` and
///     `data: null` (the request was *processed*; the *result* was
///     errored).
///   * GET-of-mutation is HTTP 405.
///   * Malformed JSON body or malformed `?variables=` is HTTP 400.
class GraphQLController extends ResourceController {
  /// Builds a controller that serves [schema] over GraphQL-over-HTTP.
  ///
  /// [dataLoaderRegistry] is an optional zero-arg factory invoked once
  /// per request. When non-null, every resolver invocation receives the
  /// minted registry through the `argumentValues['conduitDataLoaderRegistry']`
  /// channel (the same channel the conduit Request rides). The
  /// registry is dropped at request end via [DataLoaderRegistry.clear]
  /// so its loader caches don't leak across requests. When null,
  /// resolvers fall back to per-call SQL fetches with no batching —
  /// safe but quadratic for nested queries.
  GraphQLController(this.schema, {this.dataLoaderRegistry})
      : _graphql = GraphQL(schema) {
    _ensureCodecRegistered();
    acceptedContentTypes = [_applicationJson, _applicationGraphQL];
  }

  /// The schema served at this endpoint.
  ///
  /// In G1 this is hand-written by the caller. G2 will introduce a
  /// derivation path that walks `ManagedDataModel` and emits a schema
  /// directly.
  final GraphQLSchema schema;

  /// Per-request DataLoaderRegistry factory. See ctor docs.
  final DataLoaderRegistry Function()? dataLoaderRegistry;

  /// The execution engine. Constructed once per controller-runtime so
  /// schema introspection caches survive across requests.
  final GraphQL _graphql;

  // -- POST --------------------------------------------------------------

  @Operation.post()
  Future<Response> graphqlPost() async {
    final request = this.request!;
    final contentType = request.raw.headers.contentType;

    String? query;
    String? operationName;
    Map<String, dynamic> variables = const {};

    if (contentType != null &&
        contentType.primaryType == _applicationGraphQL.primaryType &&
        contentType.subType == _applicationGraphQL.subType) {
      // `application/graphql` — body is the raw query document.
      // ResourceController has already decoded the body for us; with
      // this content type we expect the decoder to have produced a
      // string (or bytes we can stringify).
      final decoded = request.body.as<dynamic>();
      if (decoded is String) {
        query = decoded;
      } else if (decoded is List<int>) {
        query = utf8.decode(decoded);
      } else {
        return _httpErrorResponse(
          HttpStatus.badRequest,
          [_GqlError('Invalid application/graphql body: expected a string.')],
          request,
        );
      }
    } else {
      // application/json envelope.
      final dynamic body = request.body.as<dynamic>();
      if (body is! Map<String, dynamic>) {
        return _httpErrorResponse(
          HttpStatus.badRequest,
          [
            _GqlError(
              'Invalid GraphQL request: body must be a JSON object with a '
              '"query" field.',
            )
          ],
          request,
        );
      }
      final dynamic q = body[_kQuery];
      if (q is! String) {
        return _httpErrorResponse(
          HttpStatus.badRequest,
          [_GqlError('Invalid GraphQL request: missing "query" field.')],
          request,
        );
      }
      query = q;
      final dynamic name = body[_kOperationName];
      if (name != null && name is! String) {
        return _httpErrorResponse(
          HttpStatus.badRequest,
          [_GqlError('Invalid GraphQL request: "operationName" must be a string.')],
          request,
        );
      }
      operationName = name as String?;
      final dynamic vars = body[_kVariables];
      if (vars != null) {
        if (vars is! Map) {
          return _httpErrorResponse(
            HttpStatus.badRequest,
            [_GqlError('Invalid GraphQL request: "variables" must be an object.')],
            request,
          );
        }
        variables = Map<String, dynamic>.from(vars);
      }
      // `extensions` is accepted but ignored in G1.
      final _ = body[_kExtensions];
    }

    return _executeAndRespond(
      query: query,
      operationName: operationName,
      variables: variables,
      allowMutations: true,
      request: request,
    );
  }

  // -- GET ---------------------------------------------------------------

  @Operation.get()
  Future<Response> graphqlGet(
    @Bind.query(_kQuery) String query, {
    @Bind.query(_kOperationName) String? operationName,
    @Bind.query(_kVariables) String? variablesJson,
  }) async {
    final request = this.request!;

    Map<String, dynamic> variables = const {};
    if (variablesJson != null) {
      try {
        final dynamic parsed = json.decode(variablesJson);
        if (parsed is! Map) {
          return _httpErrorResponse(
            HttpStatus.badRequest,
            [
              _GqlError(
                'Invalid "variables" query parameter: expected a JSON object.',
              )
            ],
            request,
          );
        }
        variables = Map<String, dynamic>.from(parsed);
      } on FormatException catch (e) {
        return _httpErrorResponse(
          HttpStatus.badRequest,
          [_GqlError('Invalid "variables" query parameter: ${e.message}')],
          request,
        );
      }
    }

    return _executeAndRespond(
      query: query,
      operationName: operationName,
      variables: variables,
      allowMutations: false,
      request: request,
    );
  }

  // -- Core --------------------------------------------------------------

  /// Parses, validates, and executes [query], formatting the response
  /// per the GraphQL-over-HTTP spec.
  ///
  /// [allowMutations] is false for GET. We pre-parse the document so we
  /// can detect the operation type before handing it to `parseAndExecute`,
  /// because the spec requires GET-of-mutation to fail with 405 (not
  /// 200/`errors`).
  Future<Response> _executeAndRespond({
    required String query,
    required String? operationName,
    required Map<String, dynamic> variables,
    required bool allowMutations,
    required Request request,
  }) async {
    // Step 1: parse. We do this ourselves so we can sniff the
    // operation type and surface parse errors as HTTP 400.
    DocumentContext document;
    try {
      final tokens = scan(query);
      final parser = Parser(tokens);
      document = parser.parseDocument();
      if (parser.errors.isNotEmpty) {
        return _httpErrorResponse(
          HttpStatus.badRequest,
          parser.errors
              .map(
                (e) => _GqlError(
                  'Syntax error: ${e.message}',
                  locations: e.span == null
                      ? const []
                      : [
                          _GqlLocation(
                            e.span!.start.line + 1,
                            e.span!.start.column + 1,
                          )
                        ],
                ),
              )
              .toList(),
          request,
        );
      }
    } on Object catch (e) {
      return _httpErrorResponse(
        HttpStatus.badRequest,
        [_GqlError('Syntax error: $e')],
        request,
      );
    }

    // Step 2: enforce GET = query-only.
    if (!allowMutations) {
      final ops = document.definitions.whereType<OperationDefinitionContext>();
      OperationDefinitionContext? selected;
      if (operationName != null) {
        selected = ops.where((op) => op.name == operationName).firstOrNull;
      } else if (ops.length == 1) {
        selected = ops.first;
      }
      if (selected != null && (selected.isMutation || selected.isSubscription)) {
        return Response(
          HttpStatus.methodNotAllowed,
          {HttpHeaders.allowHeader: 'POST'},
          {
            'errors': [
              {
                'message':
                    'GraphQL ${selected.isMutation ? "mutations" : "subscriptions"} '
                    'must use HTTP POST.',
              }
            ]
          },
        )..contentType = _negotiatedJsonContentType(request);
      }
    }

    // Step 2b: validate that selected fields exist on their parent
    // type. graphql_server2 6.5.0 silently skips unknown fields rather
    // than rejecting them; we add a minimal pre-validation pass so
    // typos and stale clients surface as HTTP 400 / `errors[]` per the
    // GraphQL-over-HTTP spec.
    final validationErrors = _validateFieldExistence(document, schema);
    if (validationErrors.isNotEmpty) {
      return _httpErrorResponse(
        HttpStatus.badRequest,
        validationErrors,
        request,
      );
    }

    // Step 3: execute. Mint a per-request DataLoaderRegistry if the
    // caller wired one — the registry rides on the same globals
    // channel as the conduit Request, since graphql_server2 6.5.0
    // merges globals into argumentValues at every resolver invocation.
    final registry = dataLoaderRegistry?.call();
    try {
      return await _runExecute(
        query: query,
        operationName: operationName,
        variables: variables,
        request: request,
        registry: registry,
      );
    } finally {
      // Drop loader caches at request end so they can't outlive the
      // request scope. (Cache lifetime is the whole point — but it's
      // bounded by the request, never longer.)
      registry?.clear();
    }
  }

  /// Inner executor split out from [_executeAndRespond] so the
  /// surrounding try/finally can drain the [DataLoaderRegistry] no
  /// matter which return path the executor takes.
  Future<Response> _runExecute({
    required String query,
    required String? operationName,
    required Map<String, dynamic> variables,
    required Request request,
    required DataLoaderRegistry? registry,
  }) async {
    try {
      final dynamic data = await _graphql.parseAndExecute(
        query,
        operationName: operationName,
        variableValues: variables,
        // Make the conduit Request available to resolvers (G3+ will
        // need this for auth + dependency injection).
        globalVariables: <String, dynamic>{
          'conduitRequest': request,
          // Null-aware element entry: omits the key entirely when no
          // registry is wired (G2 / G1 callers).
          dataLoaderRegistryArgKey: ?registry,
        },
      );

      if (data is Stream) {
        // Subscriptions are out of scope; if someone hand-rolls a
        // subscription type, the spec says reject with an explicit
        // error rather than streaming.
        return _httpErrorResponse(
          HttpStatus.badRequest,
          [_GqlError('Subscriptions are not supported over HTTP.')],
          request,
        );
      }

      return _jsonResponse(
        HttpStatus.ok,
        {'data': data},
        request,
      );
    } on GraphQLException catch (e) {
      // graphql_server2 throws GraphQLException for all server-side
      // failures it can attribute (variable coercion, missing required
      // operation, etc.). Per the GraphQL-over-HTTP spec these are
      // *request errors* and warrant HTTP 400 — the request was not
      // executable.
      return _httpErrorResponse(
        HttpStatus.badRequest,
        e.errors.map(_GqlError.fromUpstream).toList(),
        request,
      );
    } on Object catch (e, st) {
      // Anything else is a *field error* — a resolver threw. Per
      // §7.1.2 of the GraphQL spec and the GraphQL-over-HTTP spec,
      // these are returned with HTTP 200, `data: null`, and the
      // failure represented in `errors[]`. (graphql_server2 v6.5.0
      // does not trap these into the result map itself; see the
      // README "G1 status & known limitations" section for context.)
      logger.fine(
        'GraphQL field resolver threw — surfacing as 200/errors',
        e,
        st,
      );
      return _jsonResponse(
        HttpStatus.ok,
        {
          'data': null,
          'errors': [
            _GqlError(e.toString()).toJson(),
          ],
        },
        request,
      );
    }
  }

  // -- Response helpers --------------------------------------------------

  Response _httpErrorResponse(
    int status,
    List<_GqlError> errors,
    Request request,
  ) {
    return Response(
      status,
      null,
      {'errors': errors.map((e) => e.toJson()).toList()},
    )..contentType = _negotiatedJsonContentType(request);
  }

  /// JSON-envelope response builder that honors the negotiated GraphQL
  /// content type (`application/json` by default, switching to
  /// `application/graphql-response+json` when the client asks for it).
  Response _jsonResponse(
    int status,
    Map<String, dynamic> body,
    Request request,
  ) {
    return Response(status, null, body)
      ..contentType = _negotiatedJsonContentType(request);
  }

  /// Picks the JSON-family content type for the response based on the
  /// client's Accept header, defaulting to `application/json`.
  ContentType _negotiatedJsonContentType(Request request) {
    for (final accept in request.acceptableContentTypes) {
      if (accept.primaryType == _applicationGraphQLResponseJson.primaryType &&
          accept.subType == _applicationGraphQLResponseJson.subType) {
        return _applicationGraphQLResponseJson;
      }
    }
    return _applicationJson;
  }
}

// -- Internal error model ---------------------------------------------------

/// Internal helper bundling the four spec-defined error fields
/// (`message`, `locations`, `path`, `extensions`) with a `toJson` that
/// omits empty fields per the spec.
class _GqlError {
  _GqlError(
    this.message, {
    this.locations = const [],
    // `path` and `extensions` are part of the GraphQL spec error shape
    // but no code path inside G1 produces them yet — resolver-side
    // errors land inside graphql_server2's own envelope, and field-
    // level extensions arrive in G5. Keeping the constructor surface
    // ready avoids churn when those phases land.
    // ignore: unused_element_parameter
    this.path = const [],
    // ignore: unused_element_parameter
    this.extensions = const {},
  });

  factory _GqlError.fromUpstream(GraphQLExceptionError e) {
    return _GqlError(
      e.message,
      locations: e.locations
          .map((l) => _GqlLocation(l.line, l.column))
          .toList(),
    );
  }

  final String message;
  final List<_GqlLocation> locations;
  final List<Object> path;
  final Map<String, Object?> extensions;

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{'message': message};
    if (locations.isNotEmpty) {
      out['locations'] = locations.map((l) => l.toJson()).toList();
    }
    if (path.isNotEmpty) out['path'] = path;
    if (extensions.isNotEmpty) out['extensions'] = extensions;
    return out;
  }
}

class _GqlLocation {
  _GqlLocation(this.line, this.column);
  final int line;
  final int column;
  Map<String, int> toJson() => {'line': line, 'column': column};
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}

// -- Field-existence validator ---------------------------------------------

/// Walks each operation in [document] and reports any field that is
/// not defined on its parent type in [schema].
///
/// This is a deliberately narrow subset of the GraphQL spec's
/// validation rules — `graphql_server2` v6.5.0 silently drops unknown
/// fields rather than rejecting the request, which violates the
/// GraphQL-over-HTTP spec's expectation that validation errors come
/// back as HTTP 400 with `errors[]`. Until the upstream validator
/// lands (or we adopt a separate validator package), this catches the
/// common "typo in query" and "stale client" cases that production
/// users hit first. Fragment spreads, inline fragments, and
/// argument-shape validation are deferred to the upstream executor.
List<_GqlError> _validateFieldExistence(
  DocumentContext document,
  GraphQLSchema schema,
) {
  final errors = <_GqlError>[];
  for (final op in document.definitions.whereType<OperationDefinitionContext>()) {
    GraphQLObjectType? root;
    if (op.isMutation) {
      root = schema.mutationType;
    } else if (op.isSubscription) {
      root = schema.subscriptionType;
    } else {
      root = schema.queryType;
    }
    if (root == null) continue;
    _checkSelectionSet(op.selectionSet, root, errors);
  }
  return errors;
}

void _checkSelectionSet(
  SelectionSetContext set,
  GraphQLObjectType type,
  List<_GqlError> errors,
) {
  for (final sel in set.selections) {
    final field = sel.field;
    if (field == null) continue; // fragments handled by upstream executor
    final name = field.fieldName.alias?.name ?? field.fieldName.name;
    if (name == null) continue;
    // Introspection fields and `__typename` are universally available.
    if (name.startsWith('__')) continue;
    final defined = type.fields.firstWhereOrNull((f) => f.name == name);
    if (defined == null) {
      final span = field.fieldName.span;
      errors.add(
        _GqlError(
          'Cannot query field "$name" on type "${type.name}".',
          locations: span == null
              ? const []
              : [_GqlLocation(span.start.line + 1, span.start.column + 1)],
        ),
      );
      continue;
    }
    // Recurse into nested selection sets when the declared field is
    // itself an object type. Lists / non-null wrappers unwrap.
    final nested = field.selectionSet;
    if (nested != null) {
      final inner = _unwrapObjectType(defined.type);
      if (inner != null) {
        _checkSelectionSet(nested, inner, errors);
      }
    }
  }
}

GraphQLObjectType? _unwrapObjectType(GraphQLType type) {
  GraphQLType current = type;
  while (true) {
    if (current is GraphQLObjectType) return current;
    if (current is GraphQLNonNullableType) {
      current = current.ofType;
      continue;
    }
    if (current is GraphQLListType) {
      current = current.ofType;
      continue;
    }
    return null;
  }
}

extension _FieldsFirstOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
