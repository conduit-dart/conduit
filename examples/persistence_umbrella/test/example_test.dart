// Smoke test for the persistence-umbrella example. Verifies the channel
// boots, both stores are wired into the umbrella, and a request that
// touches both stores returns a sensible response.

import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/conduit_core.dart';
import 'package:persistence_umbrella_example/persistence_umbrella_example.dart';
import 'package:test/test.dart';

void main() {
  group('persistence_umbrella example', () {
    late Application<ExampleChannel> app;
    late HttpClient client;

    setUp(() async {
      app = Application<ExampleChannel>()
        ..options.port = 0
        ..options.address = 'localhost';
      // Run on the current isolate so the test can poke `app.channel`
      // directly (the multi-isolate path used in production puts the
      // channel in a separate isolate).
      await app.startOnCurrentIsolate();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await app.stop();
    });

    test('channel boots with both backends configured', () {
      final channel = app.channel;
      expect(channel.persistence, isNotNull);
      expect(channel.persistence!.hasSql, isTrue);
      expect(channel.persistence!.hasGraph, isTrue);
      expect(channel.persistence!.sqlContext, isNotNull);
      expect(channel.persistence!.graphContext, isNotNull);
    });

    test('GET /me/1 returns user from SQL augmented with graph friends',
        () async {
      final port = app.server.server.port;
      final req =
          await client.getUrl(Uri.parse('http://localhost:$port/me/1'));
      final resp = await req.close();
      expect(resp.statusCode, 200);

      final body = jsonDecode(await resp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      expect(body['user'], isNotNull);
      expect(body['user']['name'], 'Ada Lovelace');
      expect(body['friends'], [2]);
    });

    test('GET /me/2 returns the other seeded user', () async {
      final port = app.server.server.port;
      final req =
          await client.getUrl(Uri.parse('http://localhost:$port/me/2'));
      final resp = await req.close();
      expect(resp.statusCode, 200);

      final body = jsonDecode(await resp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      expect(body['user']['name'], 'Grace Hopper');
      expect(body['friends'], [1]);
    });

    test('GET /me/999 returns 404 for an unknown user', () async {
      final port = app.server.server.port;
      final req =
          await client.getUrl(Uri.parse('http://localhost:$port/me/999'));
      final resp = await req.close();
      expect(resp.statusCode, 404);
      // Drain the body so the connection can close cleanly.
      await resp.drain<void>();
    });
  });
}
