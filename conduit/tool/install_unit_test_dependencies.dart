#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';

import 'common.dart';

late final pathToPostgresDb = join(HOME, 'postgres-db');

///
/// Script to configure an environment for running unit tests.
///
/// This script is designed for linux system that run apt.
///
/// To run this script install dcli:
///
/// ```pub global activate dcli
/// ```
///
/// Then you can run:
///
/// ```
/// ./install_unit_test_dependencies.dart
/// ```
///
/// This script:
///
/// installs a docker
/// installs the docker postgress container
/// initialises posgress with the db/accounts used for unit tests.
///
void main(List<String> args) {
  preChecks();

  installDocker();

  installDockerCompose();

  installPostgressDaemon();

  installPostgresClient();

  startPostgresDaemon();

  configurePostgress(pathToPostgresDb);
}

void preChecks() {
  if (!Platform.isLinux) {
    printerr(red('Currently this script only supports linux '));
    exit(1);
  }

  if (which('apt').notfound) {
    printerr(red('Currently this script only supports apt based systems '));
    exit(1);
  }
}
