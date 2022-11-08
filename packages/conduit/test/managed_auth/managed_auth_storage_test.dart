// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:io';

import 'package:conduit/conduit.dart';
import 'package:conduit/managed_auth.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:test/test.dart';

// These tests mostly duplicate authenticate_test.dart, but also add a few more
// to manage long-term storage/cleanup of tokens and related items.
void main() {
  late ManagedAuthDelegate<User> storage;
  ManagedContext? context;

  setUp(() async {
    context = await PostgresTestConfig()
        .contextWithModels([User, ManagedAuthClient, ManagedAuthToken]);

    const salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    final clients = [
      AuthClient(
        "com.stablekernel.app1",
        generatePasswordHash("kilimanjaro", salt),
        salt,
      ),
      AuthClient(
        "com.stablekernel.app2",
        generatePasswordHash("fuji", salt),
        salt,
      ),
      AuthClient.withRedirectURI(
        "com.stablekernel.redirect",
        generatePasswordHash("mckinley", salt),
        salt,
        "http://stablekernel.com/auth/redirect",
      ),
      AuthClient.public("com.stablekernel.public"),
      AuthClient.withRedirectURI(
        "com.stablekernel.redirect2",
        generatePasswordHash("gibraltar", salt),
        salt,
        "http://stablekernel.com/auth/redirect2",
      )
    ];

    await Future.wait(
      clients
          .map(
        (ac) => ManagedAuthClient()
          ..id = ac.id
          ..salt = ac.salt
          ..hashedSecret = ac.hashedSecret
          ..redirectURI = ac.redirectURI,
      )
          .map((mc) {
        final q = Query<ManagedAuthClient>(context!)..values = mc;
        return q.insert();
      }),
    );

    storage = ManagedAuthDelegate<User>(context);
  });

  tearDown(() async {
    await context?.close();
    context = null;
  });

  group("Client behavior", () {
    late AuthServer auth;

    setUp(() async {
      auth = AuthServer(storage);
    });

    test("Get client for ID", () async {
      final c = await auth.getClient("com.stablekernel.app1");
      expect(c is AuthClient, true);
    });

    test("Revoked client can no longer be accessed", () async {
      expect(await auth.getClient("com.stablekernel.app1") is AuthClient, true);
      await auth.removeClient("com.stablekernel.app1");
      expect(await auth.getClient("com.stablekernel.app1"), isNull);
    });

    test("Cannot revoke null client", () async {
      try {
        await auth.removeClient(null);
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      final q = Query<ManagedAuthClient>(context!);
      expect(await q.fetch(), hasLength(5));
    });

    test("Revoking unknown client has no impact", () async {
      await auth.removeClient("nonsense");
      final q = Query<ManagedAuthClient>(context!);
      expect(await q.fetch(), hasLength(5));
    });

    test("Can add a new public client", () async {
      final client = generateAPICredentialPair(
        "pub-id",
        null,
        hashLength: auth.hashLength,
        hashRounds: auth.hashRounds,
        hashFunction: auth.hashFunction,
      );
      await auth.addClient(client);

      final q = Query<ManagedAuthClient>(context!)
        ..where((o) => o.id).equalTo("pub-id");
      final result0 = await q.fetchOne();
      expect(result0, isNotNull);

      final result = result0!.asClient();
      expect(result.id, "pub-id");
      expect(result.hashedSecret, isNull);
      expect(result.salt, isNull);
      expect(result.redirectURI, isNull);
      expect(result.supportsScopes, false);
      expect(result.allowedScopes, isNull);
    });

    test("If client already exists, exception is thrown", () async {
      final client = generateAPICredentialPair(
        "conflict",
        null,
        hashLength: auth.hashLength,
        hashRounds: auth.hashRounds,
        hashFunction: auth.hashFunction,
      );
      await auth.addClient(client);

      try {
        await auth.addClient(client);
        fail('unreachable');
      } on QueryException catch (e) {
        expect(e.event, QueryExceptionEvent.conflict);
      }
    });

    test("If client id is null, exception is thrown", () async {
      final client = generateAPICredentialPair(
        null,
        null,
        hashLength: auth.hashLength,
        hashRounds: auth.hashRounds,
        hashFunction: auth.hashFunction,
      );

      try {
        await auth.addClient(client);
        fail('unreachable');
      } on QueryException catch (e) {
        expect(e.event, QueryExceptionEvent.input);
      }
    });

    test("If client has redirect uri and no secret, exception is thrown",
        () async {
      final client = AuthClient("redirect-public-id", null, null)
        ..redirectURI = "http://localhost";

      try {
        await auth.addClient(client);
        fail('unreachable');
        // ignore: empty_catches
      } on ArgumentError {}
    });

    test("Client retains its allowed scopes", () async {
      final client = generateAPICredentialPair(
        "confidential-id",
        "foobar",
        redirectURI: "http://localhost",
        hashLength: auth.hashLength,
        hashRounds: auth.hashRounds,
        hashFunction: auth.hashFunction,
      )..allowedScopes = ["scope"].map((s) => AuthScope(s)).toList();
      await auth.addClient(client);

      final q = Query<ManagedAuthClient>(context!)
        ..where((o) => o.id).equalTo("confidential-id");
      final result = (await q.fetchOne())!.asClient();
      expect(result.id, "confidential-id");
      expect(result.hashedSecret, isNotNull);
      expect(result.salt, isNotNull);
      expect(result.redirectURI, "http://localhost");
      expect(result.supportsScopes, isTrue);
      expect(result.allowsScope(AuthScope("scope")), true);
      expect(result.allowsScope(AuthScope("fooar")), false);
    });
  });

  group("Token behavior via authenticate", () {
    late AuthServer auth;
    late User createdUser;
    setUp(() async {
      auth = AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
    });

    test(
        "Can create token with all information + refresh token if client is confidential",
        () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      final now = DateTime.now().toUtc();
      expect(
        token.issueDate!.isBefore(now) ||
            token.issueDate!.isAtSameMomentAs(now),
        true,
      );
      expect(token.expirationDate!.isAfter(now), true);
    });

    test(
        "Can create token with all information minus refresh token if client is public",
        () async {
      var token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.public",
        "",
      );
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      var now = DateTime.now().toUtc();
      expect(
        token.issueDate!.isBefore(now) ||
            token.issueDate!.isAtSameMomentAs(now),
        true,
      );
      expect(token.expirationDate!.isAfter(now), true);

      token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.public",
        null,
      );
      expect(token.accessToken, isString);
      expect(token.refreshToken, isNull);
      expect(token.clientID, "com.stablekernel.public");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      now = DateTime.now().toUtc();
      expect(
        token.issueDate!.isBefore(now) ||
            token.issueDate!.isAtSameMomentAs(now),
        true,
      );
      expect(token.expirationDate!.isAfter(now), true);
    });

    test("Can create token if client has redirect uri", () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
        "mckinley",
      );
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
    });

    test("Create token fails if username is incorrect", () async {
      try {
        await auth.authenticate(
          "nonsense",
          User.defaultPassword,
          "com.stablekernel.app1",
          "kilimanjaro",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if password is incorrect", () async {
      try {
        await auth.authenticate(
          createdUser.username,
          "nonsense",
          "com.stablekernel.app1",
          "kilimanjaro",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails with wildcard password", () async {
      try {
        await auth.authenticate(
          createdUser.username,
          "%",
          "com.stablekernel.app1",
          "kilimanjaro",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if client ID doesn't exist", () async {
      try {
        await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "nonsense",
          "kilimanjaro",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if client secret doesn't match", () async {
      try {
        await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "com.stablekernel.app1",
          "nonsense",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails with wildcard client secret", () async {
      try {
        await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "com.stablekernel.app1",
          "%",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test(
        "Create token fails if client ID is confidential and secret is omitted",
        () async {
      try {
        await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "com.stablekernel.app1",
          null,
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      try {
        await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "com.stablekernel.app1",
          "",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Create token fails if client secret provided for public client",
        () async {
      try {
        await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "com.stablekernel.public",
          "nonsense",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Can create token that is verifiable", () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      await auth.verify(token.accessToken);
    });

    test("Cannot verify token that doesn't exist", () async {
      try {
        await auth.verify("nonsense");
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Cannot verify wildcard token", () async {
      await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );

      try {
        await auth.verify("%");
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Expired token cannot be verified", () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
        expiration: const Duration(seconds: 1),
      );

      sleep(const Duration(seconds: 1));

      try {
        await auth.verify(token.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });

    test("Cannot verify token if owner authentcatable is 'revoked'", () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      await auth.revokeAllGrantsForResourceOwner(createdUser.id);

      try {
        await auth.verify(token.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });
  });

  group("Refreshing token", () {
    late AuthServer auth;
    late User createdUser;
    late AuthToken initialToken;

    setUp(() async {
      auth = AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
      initialToken = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
    });

    test(
        "Can refresh token with all information + refresh token if token had refresh token",
        () async {
      final token = await auth.refresh(
        initialToken.refreshToken,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      expect(token.accessToken, isNot(initialToken.accessToken));
      expect(token.refreshToken, initialToken.refreshToken);
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.app1");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      final now = DateTime.now().toUtc();
      expect(
        token.issueDate!.isBefore(now) ||
            token.issueDate!.isAtSameMomentAs(now),
        true,
      );
      expect(token.expirationDate!.isAfter(now), true);

      expect(token.issueDate!.isAfter(initialToken.issueDate!), true);
      expect(
        token.issueDate!.difference(token.expirationDate!),
        initialToken.issueDate!.difference(initialToken.expirationDate!),
      );

      final authorization = await auth.verify(token.accessToken);
      expect(authorization.clientID, "com.stablekernel.app1");
      expect(authorization.ownerID, initialToken.resourceOwnerIdentifier);
    });

    test("Can refresh token if client has redirect uri", () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
        "mckinley",
      );

      final refreshToken = await auth.refresh(
        token.refreshToken,
        "com.stablekernel.redirect",
        "mckinley",
      );
      expect(refreshToken.accessToken, isString);
      expect(refreshToken.refreshToken, isString);
      expect(refreshToken.clientID, "com.stablekernel.redirect");
    });

    test("After refresh, the previous token cannot be used", () async {
      await auth.refresh(
        initialToken.refreshToken,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      try {
        await auth.verify(initialToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Make sure we don't have duplicates in the db
      final q = Query<ManagedAuthToken>(context!);
      expect(await q.fetch(), hasLength(1));
    });

    test("Cannot refresh token that has not been issued", () async {
      try {
        await auth.refresh("nonsense", "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token that is null", () async {
      try {
        await auth.refresh(null, "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh wildcard token", () async {
      try {
        await auth.refresh("%", "com.stablekernel.app1", "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client id is missing", () async {
      try {
        await auth.refresh(initialToken.refreshToken, null, "kilimanjaro");
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client id does not match issuing client",
        () async {
      try {
        await auth.refresh(
          initialToken.refreshToken,
          "com.stablekernel.app2",
          "fuji",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is missing", () async {
      try {
        await auth.refresh(
          initialToken.refreshToken,
          "com.stablekernel.app1",
          null,
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if client secret is incorrect", () async {
      try {
        await auth.refresh(
          initialToken.refreshToken,
          "com.stablekernel.app1",
          "nonsense",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Cannot refresh token if owner authentcatable is 'revoked'", () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      await auth.revokeAllGrantsForResourceOwner(createdUser.id);

      try {
        await auth.refresh(
          token.accessToken,
          "com.stablekernel.redirect",
          "mckinley",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });
  });

  group("Generating auth code", () {
    late AuthServer auth;
    late User createdUser;

    setUp(() async {
      auth = AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      final authCode = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );

      expect(authCode.code!.length, greaterThan(0));
      expect(authCode.resourceOwnerIdentifier, createdUser.id);
      expect(authCode.clientID, "com.stablekernel.redirect");

      final now = DateTime.now().toUtc();
      expect(
        authCode.issueDate!.isBefore(now) ||
            authCode.issueDate!.isAtSameMomentAs(now),
        true,
      );
      expect(authCode.expirationDate!.isAfter(now), true);

      final token = await auth.exchange(
        authCode.code,
        "com.stablekernel.redirect",
        "mckinley",
      );
      expect(token.accessToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.refreshToken, isString);
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");
      expect(
        token.expirationDate!.difference(DateTime.now().toUtc()).inSeconds,
        greaterThan(3500),
      );
      expect(
        token.issueDate!.difference(DateTime.now().toUtc()).inSeconds.abs(),
        lessThan(2),
      );
    });

    test("Generate auth code with bad username fails", () async {
      try {
        await auth.authenticateForCode(
          "bob+0@stable",
          User.defaultPassword,
          "com.stablekernel.redirect",
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client!.id, "com.stablekernel.redirect");
        expect(e.reason, AuthRequestError.accessDenied);
      }
    });

    test("Generate auth code with bad password fails", () async {
      try {
        await auth.authenticateForCode(
          createdUser.username,
          "foobaraxegri%",
          "com.stablekernel.redirect",
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client!.id, "com.stablekernel.redirect");
        expect(e.reason, AuthRequestError.accessDenied);
      }
    });

    test("Generate auth code with wildcard password fails", () async {
      try {
        await auth.authenticateForCode(
          createdUser.username,
          "%",
          "com.stablekernel.redirect",
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client!.id, "com.stablekernel.redirect");
        expect(e.reason, AuthRequestError.accessDenied);
      }
    });

    test("Generate auth code with unknown client id fails", () async {
      try {
        await auth.authenticateForCode(
          createdUser.username,
          User.defaultPassword,
          "com.stabl",
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidClient);
      }
    });

    test("Generate auth code with no redirect uri fails", () async {
      try {
        await auth.authenticateForCode(
          createdUser.username,
          User.defaultPassword,
          "com.stablekernel.app1",
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client!.id, "com.stablekernel.app1");
        expect(e.reason, AuthRequestError.unauthorizedClient);
      }
    });

    test("Generate auth code with no client id", () async {
      try {
        await auth.authenticateForCode(
          createdUser.username,
          User.defaultPassword,
          null,
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.client, isNull);
        expect(e.reason, AuthRequestError.invalidClient);
      }
    });

    test("Code no longer available if owner authentcatable is 'revoked'",
        () async {
      final authCode = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      await auth.revokeAllGrantsForResourceOwner(createdUser.id);

      try {
        await auth.exchange(
          authCode.code,
          "com.stablekernel.redirect",
          "mckinley",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });
  });

  group("Exchanging auth code", () {
    late AuthServer auth;
    late User createdUser;
    late AuthCode code;

    setUp(() async {
      auth = AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;
      code = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
    });

    test("Can create an auth code that can be exchanged for a token", () async {
      final token = await auth.exchange(
        code.code,
        "com.stablekernel.redirect",
        "mckinley",
      );
      expect(token.accessToken, isString);
      expect(token.refreshToken, isString);
      expect(token.clientID, "com.stablekernel.redirect");
      expect(token.resourceOwnerIdentifier, createdUser.id);
      expect(token.type, "bearer");

      final now = DateTime.now().toUtc();
      expect(
        token.issueDate!.isBefore(now) ||
            token.issueDate!.isAtSameMomentAs(now),
        true,
      );
      expect(token.expirationDate!.isAfter(now), true);
    });

    test("Null code fails", () async {
      try {
        await auth.exchange(null, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Wildcard code fails", () async {
      try {
        await auth.exchange("%", "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Code that doesn't exist fails", () async {
      try {
        await auth.exchange("foobar", "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Expired code fails and it gets deleted", () async {
      code = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
        expirationInSeconds: 1,
      );

      sleep(const Duration(seconds: 1));

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      final q = Query<ManagedAuthToken>(context!)
        ..where((o) => o.code).equalTo(code.code);
      expect(await q.fetch(), isEmpty);
    });

    test("Code that has been exchanged already fails, issued token is revoked",
        () async {
      final issuedToken = await auth.exchange(
        code.code,
        "com.stablekernel.redirect",
        "mckinley",
      );

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Ensure that the associated auth code is also destroyed
      final authCodeQuery = Query<ManagedAuthToken>(context!);
      expect(await authCodeQuery.fetch(), isEmpty);
    });

    test(
        "Code that has been exchanged already fails, issued and refreshed tokens are revoked",
        () async {
      final issuedToken = await auth.exchange(
        code.code,
        "com.stablekernel.redirect",
        "mckinley",
      );
      final refreshedToken = await auth.refresh(
        issuedToken.refreshToken,
        "com.stablekernel.redirect",
        "mckinley",
      );

      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      // Can no longer use issued token
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Can no longer use refreshed token
      try {
        await auth.verify(refreshedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      // Ensure that the associated auth code is also destroyed
      final authCodeQuery = Query<ManagedAuthToken>(context!);
      expect(await authCodeQuery.fetch(), isEmpty);
    });

    test("Null client ID fails", () async {
      try {
        await auth.exchange(code.code, null, "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Unknown client ID fails", () async {
      try {
        await auth.exchange(code.code, "nonsense", "mckinley");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Different client ID than the one that generated code fials",
        () async {
      try {
        await auth.exchange(
          code.code,
          "com.stablekernel.redirect2",
          "gibraltar",
        );

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("No client secret fails", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", null);

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });

    test("Wrong client secret fails", () async {
      try {
        await auth.exchange(code.code, "com.stablekernel.redirect", "nonsense");

        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}
    });
  });

  group("Cleanup/friendly fire scenarios from client", () {
    late List<User> createdUsers;

    late AuthServer auth;

    setUp(() async {
      auth = AuthServer(storage);
      createdUsers = await createUsers(context, 3);
    });

    test("Revoking a client revokes all of its tokens and auth codes",
        () async {
      final unusedCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final exchangedCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final exchangedToken = await auth.exchange(
        exchangedCode.code,
        "com.stablekernel.redirect",
        "mckinley",
      );
      final issuedToken = await auth.authenticate(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
        "mckinley",
      );

      expect(await auth.verify(issuedToken.accessToken), isNotNull);

      await auth.removeClient("com.stablekernel.redirect");
      try {
        await auth.exchange(
          unusedCode.code,
          "com.stablekernel.redirect",
          "mckinley",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      try {
        await auth.verify(exchangedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      final tokenQuery = Query<ManagedAuthToken>(context!);
      expect(await tokenQuery.fetch(), isEmpty);
    });

    test(
        "Revoking a client does not invalidate tokens or codes issued by other clients",
        () async {
      final exchangedCodeRevoke = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      await auth.exchange(
        exchangedCodeRevoke.code,
        "com.stablekernel.redirect",
        "mckinley",
      );
      await auth.authenticate(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
        "mckinley",
      );

      final unusedCodeKeep = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect2",
      );
      final exchangedCodeKeep = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect2",
      );
      final exchangedTokenKeep = await auth.exchange(
        exchangedCodeKeep.code,
        "com.stablekernel.redirect2",
        "gibraltar",
      );
      final issuedTokenKeep = await auth.authenticate(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect2",
        "gibraltar",
      );

      await auth.removeClient("com.stablekernel.redirect");

      final exchangedLater = await auth.exchange(
        unusedCodeKeep.code,
        "com.stablekernel.redirect2",
        "gibraltar",
      );
      expect(
        await auth.verify(exchangedLater.accessToken),
        const TypeMatcher<Authorization>(),
      );
      expect(
        await auth.verify(exchangedTokenKeep.accessToken),
        const TypeMatcher<Authorization>(),
      );
      expect(
        await auth.verify(issuedTokenKeep.accessToken),
        const TypeMatcher<Authorization>(),
      );

      final tokenQuery = Query<ManagedAuthToken>(context!);
      expect(await tokenQuery.fetch(), hasLength(3));
    });

    test("Clients retain their token ownership", () async {
      final createdUser = createdUsers.first;

      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      var p1 = await auth.verify(token.accessToken);
      expect(p1.clientID, "com.stablekernel.app1");
      expect(p1.ownerID, createdUser.id);

      final code = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final token2 = await auth.exchange(
        code.code,
        "com.stablekernel.redirect",
        "mckinley",
      );

      p1 = await auth.verify(token.accessToken);
      expect(p1.clientID, "com.stablekernel.app1");
      expect(p1.ownerID, createdUser.id);

      final p2 = await auth.verify(token2.accessToken);
      expect(p2.clientID, "com.stablekernel.redirect");
      expect(p2.ownerID, createdUser.id);
    });
  });

  group("Cleanup/friendly fire on Authenticatable", () {
    late List<User> createdUsers;

    late AuthServer auth;

    setUp(() async {
      auth = AuthServer(storage);
      createdUsers = await createUsers(context, 3);
    });

    test(
        "After explicitly invoking 'invalidate resource owner' method, all tokens and codes for that resource owner are no longer in db",
        () async {
      final unusedCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final exchangedCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final exchangedToken = await auth.exchange(
        exchangedCode.code,
        "com.stablekernel.redirect",
        "mckinley",
      );
      final issuedToken = await auth.authenticate(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );

      expect(await auth.verify(issuedToken.accessToken), isNotNull);

      await auth.revokeAllGrantsForResourceOwner(createdUsers.first.id);

      try {
        await auth.exchange(
          unusedCode.code,
          "com.stablekernel.redirect",
          "mckinley",
        );
        expect(true, false);
        // ignore: empty_catches
      } on AuthServerException {}

      try {
        await auth.verify(exchangedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
      try {
        await auth.verify(issuedToken.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }

      final tokenQuery = Query<ManagedAuthToken>(context!);
      expect(await tokenQuery.fetch(), isEmpty);
    });
  });

  group("Code friendly fire/cleanup", () {
    late List<User> createdUsers;

    late AuthServer auth;

    setUp(() async {
      final limitedStorage = ManagedAuthDelegate<User>(context, tokenLimit: 3);
      auth = AuthServer(limitedStorage);
      createdUsers = await createUsers(context, 3);
    });

    test("Revoking a token automatically deletes the code that generated it",
        () async {
      final exchangedCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final exchangedToken = await auth.exchange(
        exchangedCode.code,
        "com.stablekernel.redirect",
        "mckinley",
      );

      final codeQuery = Query<ManagedAuthToken>(context!)
        ..where((o) => o.code).equalTo(exchangedCode.code);
      expect(await codeQuery.fetch(), hasLength(1));

      final tokenQuery = Query<ManagedAuthToken>(context!)
        ..where((o) => o.accessToken).equalTo(exchangedToken.accessToken);
      await tokenQuery.delete();

      expect(await codeQuery.fetch(), isEmpty);
    });

    test(
        "Oldest codes gets pruned after reaching limit, but only for that user",
        () async {
      // Insert a code manually to simulate a race condition, but insert it after the others have been
      // so they don't strip it when inserted.
      var manualCode = ManagedAuthToken()
        ..code = "ASDFGHJ"
        ..issueDate = DateTime.now().toUtc()
        ..expirationDate =
            DateTime.now().add(const Duration(seconds: 60)).toUtc()
        ..client = (ManagedAuthClient()..id = "com.stablekernel.redirect")
        ..resourceOwner = (User()..id = createdUsers.first.id);

      // Insert a code for a different user to make sure it doesn't get pruned.
      final otherUserCode = await auth.authenticateForCode(
        createdUsers[1].username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );

      // Insert the max number of codes
      final codes = <AuthCode>[];
      for (var i = 0; i < 3; i++) {
        final c = await auth.authenticateForCode(
          createdUsers.first.username,
          User.defaultPassword,
          "com.stablekernel.redirect",
        );
        codes.add(c);
        await Future.delayed(const Duration(milliseconds: 3));
      }

      // Insert the 'race condition' code
      final manualInsertQuery = Query<ManagedAuthToken>(context!)
        ..values = manualCode;
      manualCode = await manualInsertQuery.insert();

      // Make a new code, should kill the race condition code and the first generated code in the loop.
      // Other user codes remain
      final newCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect",
      );
      final codeQuery = Query<ManagedAuthToken>(context!);
      var codesInDB = (await codeQuery.fetch()).map((ac) => ac.code).toList();

      // These codes are in chronological order
      expect(codesInDB.contains(otherUserCode.code), true);

      expect(codesInDB.contains(manualCode.code), false);
      expect(codesInDB.contains(codes.first.code), false);
      expect(codesInDB.contains(codes[1].code), true);
      expect(codesInDB.contains(codes.last.code), true);
      expect(codesInDB.contains(newCode.code), true);

      // Make a new code, but with a different client, should still kill off the oldest expiring code.
      final lastCode = await auth.authenticateForCode(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.redirect2",
      );
      codesInDB = (await codeQuery.fetch()).map((ac) => ac.code).toList();

      // These codes are in chronological order
      expect(codesInDB.contains(otherUserCode.code), true);

      expect(codesInDB.contains(codes[1].code), false);
      expect(codesInDB.contains(codes.last.code), true);
      expect(codesInDB.contains(newCode.code), true);
      expect(codesInDB.contains(lastCode.code), true);
    });
  });

  group("Token friendly fire/cleanup", () {
    late List<User> createdUsers;

    late AuthServer auth;

    setUp(() async {
      final limitedStorage = ManagedAuthDelegate<User>(context, tokenLimit: 3);
      auth = AuthServer(limitedStorage);
      createdUsers = await createUsers(context, 10);
    });

    test(
        "Oldest tokens gets pruned after reaching tokenLimit, but only for that user",
        () async {
      // Insert a token manually to simulate a race condition, but insert it after the others have been
      // so they don't strip it when inserted.
      var manualToken = ManagedAuthToken()
        ..accessToken = "ASDFGHJ"
        ..refreshToken = "ABCHASDS"
        ..issueDate = DateTime.now().toUtc()
        ..expirationDate =
            DateTime.now().add(const Duration(seconds: 60)).toUtc()
        ..client = (ManagedAuthClient()..id = "com.stablekernel.app1")
        ..resourceOwner = (User()..id = createdUsers.first.id);

      // Insert a token for a different user to make sure it doesn't get pruned.
      final otherUserToken = await auth.authenticate(
        createdUsers[1].username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );

      // Insert the max number of token
      final tokens = <AuthToken>[];
      for (var i = 0; i < 3; i++) {
        final c = await auth.authenticate(
          createdUsers.first.username,
          User.defaultPassword,
          "com.stablekernel.app1",
          "kilimanjaro",
        );
        await Future.delayed(const Duration(milliseconds: 3));
        tokens.add(c);
      }

      // Insert the 'race condition' token
      final manualInsertQuery = Query<ManagedAuthToken>(context!)
        ..values = manualToken;
      manualToken = await manualInsertQuery.insert();

      // Make a new token, should kill the race condition token and the first generated token in the loop.
      // Other user token remain
      final newToken = await auth.authenticate(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      final tokenQuery = Query<ManagedAuthToken>(context!);
      var tokensInDB =
          (await tokenQuery.fetch()).map((ac) => ac.accessToken).toList();

      // These token are in chronological order
      expect(tokensInDB.contains(otherUserToken.accessToken), true);

      expect(tokensInDB.contains(manualToken.accessToken), false);
      expect(tokensInDB.contains(tokens.first.accessToken), false);
      expect(tokensInDB.contains(tokens[1].accessToken), true);
      expect(tokensInDB.contains(tokens.last.accessToken), true);
      expect(tokensInDB.contains(newToken.accessToken), true);

      // Make a new token, but with a different client, should still kill off the oldest token code.
      final lastToken = await auth.authenticate(
        createdUsers.first.username,
        User.defaultPassword,
        "com.stablekernel.app2",
        "fuji",
      );
      tokensInDB =
          (await tokenQuery.fetch()).map((ac) => ac.accessToken).toList();

      // These token are in chronological order
      expect(tokensInDB.contains(otherUserToken.accessToken), true);

      expect(tokensInDB.contains(tokens[1].accessToken), false);
      expect(tokensInDB.contains(tokens.last.accessToken), true);
      expect(tokensInDB.contains(newToken.accessToken), true);
      expect(tokensInDB.contains(lastToken.accessToken), true);
    });

    test("Ensure users aren't authenticated by other users", () async {
      final t1 = await auth.authenticate(
        createdUsers[0].username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      final t2 = await auth.authenticate(
        createdUsers[4].username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );

      var permission = await auth.verify(t1.accessToken);
      expect(permission.clientID, "com.stablekernel.app1");
      expect(permission.ownerID, createdUsers[0].id);

      permission = await auth.verify(t2.accessToken);
      expect(permission.clientID, "com.stablekernel.app1");
      expect(permission.ownerID, createdUsers[4].id);
    });

    test(
        "Revoking tokens/codes for Authenticatable does not impact other Authenticatables",
        () async {
      final t1 = await auth.authenticate(
        createdUsers[0].username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );
      final t2 = await auth.authenticate(
        createdUsers[4].username,
        User.defaultPassword,
        "com.stablekernel.app1",
        "kilimanjaro",
      );

      await auth.revokeAllGrantsForResourceOwner(createdUsers[0].id);
      expect(await auth.verify(t2.accessToken), isNotNull);

      try {
        await auth.verify(t1.accessToken);
        fail("unreachable");
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidGrant);
      }
    });
  });

  group("Scoping cases", () {
    late AuthServer auth;
    late User createdUser;
    setUp(() async {
      auth = AuthServer(storage);
      createdUser = (await createUsers(context, 1)).first;

      const salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";

      final clients = [
        AuthClient.public(
          "all",
          allowedScopes: [
            AuthScope("user"),
            AuthScope("location:add"),
            AuthScope("admin:settings.readonly")
          ],
        ),
        AuthClient.public(
          "subset",
          allowedScopes: [
            AuthScope("user.readonly"),
            AuthScope("location:view")
          ],
        ),
        AuthClient.public(
          "subset.multiple",
          allowedScopes: [AuthScope("user:a"), AuthScope("user:b")],
        ),
        AuthClient.withRedirectURI(
          "all.redirect",
          generatePasswordHash("a", salt),
          salt,
          "http://a.com",
          allowedScopes: [
            AuthScope("user"),
            AuthScope("location:add"),
            AuthScope("admin:settings.readonly")
          ],
        ),
        AuthClient.withRedirectURI(
          "subset.redirect",
          generatePasswordHash("b", salt),
          salt,
          "http://b.com",
          allowedScopes: [
            AuthScope("user.readonly"),
            AuthScope("location:view")
          ],
        ),
      ];

      await Future.wait(
        clients
            .map(
          (ac) => ManagedAuthClient()
            ..id = ac.id
            ..salt = ac.salt
            ..allowedScope =
                ac.allowedScopes!.map((a) => a.toString()).join(" ")
            ..hashedSecret = ac.hashedSecret
            ..redirectURI = ac.redirectURI,
        )
            .map((mc) {
          final q = Query<ManagedAuthClient>(context!)..values = mc;
          return q.insert();
        }),
      );
    });

    // -- Password grant --

    test(
        "Client can issue tokens for valid scope, only include specified scope",
        () async {
      final token1 = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all",
        null,
        requestedScopes: [AuthScope("user")],
      );

      expect(token1.scopes!.length, 1);
      expect(token1.accessToken, isNotNull);
      expect(token1.scopes!.first.isExactly("user"), true);

      final token2 = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all",
        null,
        requestedScopes: [AuthScope("user:sub")],
      );

      expect(token2.scopes!.length, 1);
      expect(token2.accessToken, isNotNull);
      expect(token2.scopes!.first.isExactly("user:sub"), true);
    });

    test(
        "Client can request multiple scopes and if all are valid, get token and all specified scopes",
        () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all",
        null,
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );

      expect(token.scopes!.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user")), true);
      expect(token.scopes!.any((s) => s.isExactly("location:add")), true);
    });

    test(
        "Client that requests multiple scopes for token where one is not valid, only get valid scopes",
        () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all",
        null,
        requestedScopes: [AuthScope("user"), AuthScope("unknown")],
      );

      expect(token.scopes!.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user")), true);
    });

    test(
        "Client that requests multiple scopes where they are subsets of valid scopes, gets subsets back",
        () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all",
        null,
        requestedScopes: [AuthScope("user:sub"), AuthScope("location:add:sub")],
      );

      expect(token.scopes!.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user:sub")), true);
      expect(token.scopes!.any((s) => s.isExactly("location:add:sub")), true);
    });

    test("Client that requests allowed nested scope gets token", () async {
      var token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "subset.multiple",
        null,
        requestedScopes: [
          AuthScope("user:a"),
        ],
      );
      expect(token.scopes!.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user:a")), true);

      token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "subset.multiple",
        null,
        requestedScopes: [
          AuthScope("user:b"),
        ],
      );
      expect(token.scopes!.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user:b")), true);

      try {
        final _ = await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "subset.multiple",
          null,
          requestedScopes: [
            AuthScope("user"),
          ],
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test("Client will reject token request for unknown scope", () async {
      try {
        final _ = await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "all",
          null,
          requestedScopes: [AuthScope("unknown")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Client will reject token request for scope with too high of privileges",
        () async {
      try {
        final _ = await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "all",
          null,
          requestedScopes: [AuthScope("location")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Client will reject token request for scope that has limiting modifier",
        () async {
      try {
        final _ = await auth.authenticate(
          createdUser.username,
          User.defaultPassword,
          "all",
          null,
          requestedScopes: [AuthScope("admin:settings")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    // --- Refresh ---

    test("Refresh token without scope specified returns same scope", () async {
      var token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        "a",
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );

      token = await auth.refresh(token.refreshToken, "all.redirect", "a");
      expect(token.scopes!.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user")), true);
      expect(token.scopes!.any((s) => s.isExactly("location:add")), true);
    });

    test("Refresh token with lesser scope specified returns specified scope",
        () async {
      var token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        "a",
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );

      token = await auth.refresh(
        token.refreshToken,
        "all.redirect",
        "a",
        requestedScopes: [
          AuthScope("user"),
          AuthScope("location:add.modifier")
        ],
      );
      expect(token.scopes!.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user")), true);
      expect(
        token.scopes!.any((s) => s.isExactly("location:add.modifier")),
        true,
      );

      token = await auth.refresh(
        token.refreshToken,
        "all.redirect",
        "a",
        requestedScopes: [
          AuthScope("user:under"),
        ],
      );
      expect(token.scopes!.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user:under")), true);
    });

    test(
        "Refresh token with new, valid scope fails because refresh can't upgrade scope",
        () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        "a",
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );

      try {
        final _ = await auth.refresh(
          token.refreshToken,
          "all.redirect",
          "a",
          requestedScopes: [
            AuthScope("user"),
            AuthScope("location:add"),
            AuthScope("admin:settings.readonly")
          ],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Refresh token request with higher privileged scope does not include that scope because refresh can't upgrade scope",
        () async {
      final token = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        "a",
        requestedScopes: [AuthScope("user:foo"), AuthScope("location:add")],
      );

      try {
        final _ = await auth.refresh(
          token.refreshToken,
          "all.redirect",
          "a",
          requestedScopes: [AuthScope("user")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Refresh token request after client has been modified to limit previous granted scope fails",
        () async {
      // token1 will have explicit refresh scope, token2 will have implicit refresh scope
      final token1 = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        "a",
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );
      final token2 = await auth.authenticate(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        "a",
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );

      final q = Query<ManagedAuthClient>(context!)
        ..where((o) => o.id).equalTo("all.redirect")
        ..values.allowedScope = "user location:add.readonly";
      await q.updateOne();

      try {
        final _ = await auth.refresh(
          token1.refreshToken,
          "all.redirect",
          "a",
          requestedScopes: [AuthScope("user"), AuthScope("location:add")],
        );
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }

      try {
        final _ = await auth.refresh(token2.refreshToken, "all.redirect", "a");
        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    // --- Auth code ---

    test("Client can issue auth code for valid scope", () async {
      final code1 = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        requestedScopes: [AuthScope("user")],
      );
      final token1 = await auth.exchange(code1.code, "all.redirect", "a");

      expect(token1.scopes!.length, 1);
      expect(token1.accessToken, isNotNull);
      expect(token1.scopes!.first.isExactly("user"), true);

      final code2 = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        requestedScopes: [AuthScope("user:sub")],
      );
      final token2 = await auth.exchange(code2.code, "all.redirect", "a");

      expect(token2.scopes!.length, 1);
      expect(token2.accessToken, isNotNull);
      expect(token2.scopes!.first.isExactly("user:sub"), true);
    });

    test(
        "Client that requests multiple scopes for auth code where they are subsets of valid scopes, gets subsets back",
        () async {
      final code = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        requestedScopes: [AuthScope("user:sub"), AuthScope("location:add:sub")],
      );
      final token = await auth.exchange(code.code, "all.redirect", "a");

      expect(token.scopes!.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user:sub")), true);
      expect(token.scopes!.any((s) => s.isExactly("location:add:sub")), true);
    });

    test(
        "Client can request multiple scopes and if all are valid, get auth code",
        () async {
      final code = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        requestedScopes: [AuthScope("user"), AuthScope("location:add")],
      );

      final token = await auth.exchange(code.code, "all.redirect", "a");

      expect(token.scopes!.length, 2);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user")), true);
      expect(token.scopes!.any((s) => s.isExactly("location:add")), true);
    });

    test(
        "Client that requests multiple scopes for auth code where one is not valid, only get valid scopes",
        () async {
      final code = await auth.authenticateForCode(
        createdUser.username,
        User.defaultPassword,
        "all.redirect",
        requestedScopes: [AuthScope("user"), AuthScope("unknown")],
      );

      final token = await auth.exchange(code.code, "all.redirect", "a");
      expect(token.scopes!.length, 1);
      expect(token.accessToken, isNotNull);
      expect(token.scopes!.any((s) => s.isExactly("user")), true);
    });

    test("Client will reject auth code request for unknown scope", () async {
      try {
        final _ = await auth.authenticateForCode(
          createdUser.username,
          User.defaultPassword,
          "all.redirect",
          requestedScopes: [AuthScope("unknown")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Client will reject auth code request for scope with too high of privileges",
        () async {
      try {
        final _ = await auth.authenticateForCode(
          createdUser.username,
          User.defaultPassword,
          "all.redirect",
          requestedScopes: [AuthScope("location")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });

    test(
        "Client will reject auth code request for scope that has limiting modifier",
        () async {
      try {
        final _ = await auth.authenticateForCode(
          createdUser.username,
          User.defaultPassword,
          "all.redirect",
          requestedScopes: [AuthScope("admin:settings")],
        );

        expect(true, false);
      } on AuthServerException catch (e) {
        expect(e.reason, AuthRequestError.invalidScope);
      }
    });
  });
}

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner<_User> {
  static const String defaultPassword = "foobaraxegrind!%12";
}

class _User extends ResourceOwnerTableDefinition {}

Future<List<User>> createUsers(ManagedContext? ctx, int count) async {
  final list = <User>[];
  for (int i = 0; i < count; i++) {
    final salt = generateRandomSalt();
    final u = User()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword = generatePasswordHash(User.defaultPassword, salt);

    final q = Query<User>(ctx!)..values = u;

    list.add(await q.insert());
  }
  return list;
}
