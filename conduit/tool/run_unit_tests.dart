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

  DartSdk().runPubGet('..');

  startPostgresDaemon();

  print('Starting postgres docker image');

  print('Staring Conduit unit tests');
  'pub run test -j1'.start(workingDirectory: '..');

  print('Stopping posgress docker image');
}
