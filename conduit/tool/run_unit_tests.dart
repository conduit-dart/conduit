#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:conduit_common_test/conduit_common_test.dart';

/// This script will run the conduit unit tests
///
/// To run this script install dcli:
///
/// ```pub global activate dcli
/// ```
///
/// Then you can run:
///
/// ```
/// ./run_unit_tests.dart
/// ```
///

void main(List<String> args) {
  if (which('psql').notfound) {
    printerr(red(
        'Postgres not found. Have you run "install_unit_test_dependencies.dart".'));
    exit(1);
  }

  ProcessSignal.sigint.watch().listen((signal) {
    print('ctrl-caught');
    'docker-compose down'.run;
  });
  DartSdk().runPubGet('..');

  var dbSettings = DbSettings.load();
  dbSettings.createEnvironmentVariables();

  var postgresManager = PostgresManager(dbSettings);

  if (dbSettings.useContainer) {
    print('Starting postgres docker image');
    postgresManager.startPostgresDaemon();
  }

  postgresManager.waitForPostgresToStart();

  print('recreating database');
  postgresManager.dropPostgresDb();
  postgresManager.dropUser();

  postgresManager.createPostgresDb();

  print('Staring Conduit unit tests');

  /// run the tests
  'pub run test -j1'.start(workingDirectory: '..');

  print('Stopping posgress docker image');
  postgresManager.stopPostgresDaemon();
}
