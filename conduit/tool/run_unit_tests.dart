#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';

import 'common.dart';

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

  startPostgresDaemon();

  print('Starting postgres docker image');

  print('Staring Conduit unit tests');

  env['POSTGRES_USER'] = 'conduit_test_user';
  env['POSTGRES_PASSWORD'] = '34achfAdce';
  env['POSTGRES_DB'] = 'conduit_test_db';

  /// run the tests
  'pub run test -j1'.start(workingDirectory: '..');

  print('Stopping posgress docker image');
}
