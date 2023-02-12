import 'package:conduit_core/src/db/managed/backing.dart';
import 'package:conduit_core/src/db/managed/managed.dart';
import 'package:conduit_core/src/db/managed/relationship_type.dart';
import 'package:conduit_core/src/db/query/page.dart';
import 'package:conduit_core/src/db/query/query.dart';
import 'package:conduit_core/src/db/query/sort_descriptor.dart';

abstract class QueryMixin<InstanceType extends ManagedObject>
    implements Query<InstanceType> {
  @override
  int offset = 0;

  @override
  int fetchLimit = 0;

  @override
  int timeoutInSeconds = 30;

  @override
  bool canModifyAllInstances = false;

  @override
  Map<String, dynamic>? valueMap;

  @override
  QueryPredicate? predicate;

  QueryPage? pageDescriptor;
  List<QuerySortDescriptor>? sortDescriptors;
  Map<ManagedRelationshipDescription, Query>? subQueries;

  QueryMixin? _parentQuery;
  List<QueryExpression<dynamic, dynamic>> expressions = [];
  InstanceType? _valueObject;

  List<KeyPath>? _propertiesToFetch;

  List<KeyPath> get propertiesToFetch =>
      _propertiesToFetch ??
      entity.defaultProperties!
          .map((k) => KeyPath(entity.properties[k]))
          .toList();

  @override
  InstanceType get values {
    if (_valueObject == null) {
      _valueObject = entity.instanceOf() as InstanceType?;
      _valueObject!.backing = ManagedBuilderBacking.from(
        _valueObject!.entity,
        _valueObject!.backing,
      );
    }
    return _valueObject!;
  }

  @override
  set values(InstanceType? obj) {
    if (obj == null) {
      _valueObject = null;
      return;
    }

    _valueObject = entity.instanceOf(
      backing: ManagedBuilderBacking.from(entity, obj.backing),
    );
  }

  @override
  QueryExpression<T, InstanceType> where<T>(
    T Function(InstanceType x) propertyIdentifier,
  ) {
    final properties = entity.identifyProperties(propertyIdentifier);
    if (properties.length != 1) {
      throw ArgumentError(
        "Invalid property selector. Must reference a single property only.",
      );
    }

    final expr = QueryExpression<T, InstanceType>(properties.first);
    expressions.add(expr);
    return expr;
  }

  @override
  Query<T> join<T extends ManagedObject>({
    T? Function(InstanceType x)? object,
    ManagedSet<T>? Function(InstanceType x)? set,
  }) {
    final relationship = object ?? set!;
    final desc = entity.identifyRelationship(relationship);

    return _createSubquery<T>(desc);
  }

  @override
  void pageBy<T>(
    T Function(InstanceType x) propertyIdentifier,
    QuerySortOrder order, {
    T? boundingValue,
  }) {
    final attribute = entity.identifyAttribute(propertyIdentifier);
    pageDescriptor =
        QueryPage(order, attribute.name, boundingValue: boundingValue);
  }

  @override
  void sortBy<T>(
    T Function(InstanceType x) propertyIdentifier,
    QuerySortOrder order,
  ) {
    final attribute = entity.identifyAttribute(propertyIdentifier);

    sortDescriptors ??= <QuerySortDescriptor>[];
    sortDescriptors!.add(QuerySortDescriptor(attribute.name, order));
  }

  @override
  void returningProperties(
    List<dynamic> Function(InstanceType x) propertyIdentifiers,
  ) {
    final properties = entity.identifyProperties(propertyIdentifiers);

    if (properties.any(
      (kp) => kp.path.any(
        (p) =>
            p is ManagedRelationshipDescription &&
            p.relationshipType != ManagedRelationshipType.belongsTo,
      ),
    )) {
      throw ArgumentError(
        "Invalid property selector. Cannot select has-many or has-one relationship properties. Use join instead.",
      );
    }

    _propertiesToFetch = entity.identifyProperties(propertyIdentifiers);
  }

  void validateInput(Validating op) {
    if (valueMap == null) {
      if (op == Validating.insert) {
        values.willInsert();
      } else if (op == Validating.update) {
        values.willUpdate();
      }

      final ctx = values.validate(forEvent: op);
      if (!ctx.isValid) {
        throw ValidationException(ctx.errors);
      }
    }
  }

  Query<T> _createSubquery<T extends ManagedObject>(
    ManagedRelationshipDescription fromRelationship,
  ) {
    if (subQueries?.containsKey(fromRelationship) ?? false) {
      throw StateError(
        "Invalid query. Cannot join same property more than once.",
      );
    }

    // Ensure we don't cyclically join
    var parent = _parentQuery;
    while (parent != null) {
      if (parent.subQueries!.containsKey(fromRelationship.inverse)) {
        final validJoins = fromRelationship.entity.relationships!.values
            .where((r) => !identical(r, fromRelationship))
            .map((r) => "'${r!.name}'")
            .join(", ");

        throw StateError(
            "Invalid query construction. This query joins '${fromRelationship.entity.tableName}' "
            "with '${fromRelationship.inverse!.entity.tableName}' on property '${fromRelationship.name}'. "
            "However, '${fromRelationship.inverse!.entity.tableName}' "
            "has also joined '${fromRelationship.entity.tableName}' on this property's inverse "
            "'${fromRelationship.inverse!.name}' earlier in the 'Query'. "
            "Perhaps you meant to join on another property, such as: $validJoins?");
      }

      parent = parent._parentQuery;
    }

    subQueries ??= {};

    final subquery = Query<T>(context);
    (subquery as QueryMixin)._parentQuery = this;
    subQueries![fromRelationship] = subquery;

    return subquery;
  }
}
