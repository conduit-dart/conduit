// Smoke tests for the cross-source example. These exercise the
// schema-build path against the fake stores; they do not boot the
// HTTP server.

import 'package:conduit_graphql/conduit_graphql.dart';
import 'package:graphql_cross_source_example/graphql_cross_source_example.dart';
import 'package:test/test.dart';

void main() {
  test('CrossSourceChannel.prepare wires both halves', () async {
    final channel = CrossSourceChannel();
    await channel.prepare();
    addTearDown(() => channel.typedPersistence.close());

    expect(channel.typedPersistence.hasSql, isTrue);
    expect(channel.typedPersistence.hasGraph, isTrue);
    final names = channel.persistenceSchema.schema.queryType!.fields
        .map((f) => f.name)
        .toSet();
    expect(names, containsAll(['user', 'users', 'profile', 'profiles']));
  });

  test('User type carries the stitched friends field', () async {
    final channel = CrossSourceChannel();
    await channel.prepare();
    addTearDown(() => channel.typedPersistence.close());
    final userType = channel.persistenceSchema.sqlObjectTypes['User']!;
    final friendField = userType.fields.firstWhere((f) => f.name == 'friends');
    expect(friendField.type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
  });

  test(
      'Stitching resolver yields friend rows when the parent ManagedObject '
      'carries an id Map (resolver path used by graphql_server2)', () async {
    final channel = CrossSourceChannel();
    await channel.prepare();
    addTearDown(() => channel.typedPersistence.close());

    final userType = channel.persistenceSchema.sqlObjectTypes['User']!;
    final friendField =
        userType.fields.firstWhere((f) => f.name == 'friends');
    final resolver = friendField.resolve!;
    // Simulate the executor's parent-Map shortcut: handing a Map with
    // an `id` to the resolver.
    final result = await resolver(
      <String, Object?>{'id': 1},
      const <String, dynamic>{},
    );
    expect(result, isA<List>());
    final list = result! as List;
    // user 1 is friends with users 2 and 3 in the fixture.
    expect(list, hasLength(2));
  });
}
