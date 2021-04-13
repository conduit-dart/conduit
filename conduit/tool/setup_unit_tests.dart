#! /usr/bin/env dcli

import 'package:dcli/dcli.dart';

import 'package:conduit_common_test/conduit_common_test.dart';

/// late final pathToPostgresDb = join(HOME, 'postgres-db');

///
/// Script to configure an environment for running conduit unit tests.
///
/// This script is primarily designed for linux system that run apt.
///
/// If you are running an non-linux or non-apt base system this script
/// should still be used as it will warning of missing dependencies
/// and it will still configure the database container.
///
/// To run this script first install dcli:
///
/// ```pub global activate dcli
/// ```
///
/// Then you can run:
///
/// ```
/// ./setup_unit_tests.dart
/// ```
///
/// This script:
///
/// Requests the username/password/dbname etc to use.
/// installs docker
/// installs docker-compose
/// installs the docker postgres container
/// initialises posgres with the db/accounts used for unit tests.
///
void main(List<String> args) {
  var parser = ArgParser()
    ..addFlag('verbose',
        abbr: 'v',
        defaultsTo: false,
        help: 'Outputs verbose logging. WARNING passwords will be displayed');

  var parsed = parser.parse(args);

  final verbose = parsed['verbose'] as bool;
  Settings().setVerbose(enabled: verbose);

  'docker-compose down'.start(progress: Progress.devNull());
  var dbSettings = DbSettings.load();

  var nameRegExp = r'[a-zA-Z0-0\-_]+';
  var passwordRegExp = r'[a-zA-Z0-0\-_!]+';

  print(
      'The unit tests can setup a docker container running postgres or you can use an existing postgres server');
  var createPostgresContainer =
      confirm('Do you want to start a postgres docker container?');

  dbSettings.useContainer = createPostgresContainer;
  if (createPostgresContainer) {
    dbSettings.host = 'localhost';
  } else {
    dbSettings.host = ask('Test Database Host:',
        validator: Ask.any([Ask.fqdn, Ask.alphaNumeric, Ask.ipAddress()]),
        defaultValue: dbSettings.host);
  }

  print(
      'To configure the test database we need to know what username/password etc you want to use.');

  dbSettings.port = int.parse(ask('Test Database Port No.:',
      validator: Ask.all([Ask.integer, Ask.valueRange(1025, 65535)]),
      defaultValue: '${dbSettings.port}'));
  dbSettings.username = ask('Database Username:',
      validator: Ask.regExp(nameRegExp), defaultValue: dbSettings.username);
  dbSettings.password = ask('Database Password:',
      validator: Ask.regExp(passwordRegExp), defaultValue: dbSettings.password);
  dbSettings.dbName = ask('Database Name:',
      validator: Ask.regExp(nameRegExp), defaultValue: dbSettings.dbName);

  if (dbSettings.dbName != DbSettings.defaultDbName) {
    print(orange(
        'Note the database ${dbSettings.dbName} will be dropped after each unit test run'));
    while (!confirm(
        'Are you sure you want to use ${dbSettings.dbName} on ${dbSettings.host} as the database for unit testing?')) {
      dbSettings.dbName = ask('Database Name:',
          validator: Ask.regExp(nameRegExp), defaultValue: dbSettings.dbName);
    }
  }

  dbSettings.save();
  dbSettings.createEnvironmentVariables();

  final postgresManager = PostgresManager(dbSettings);

  postgresManager.installPostgresClient();
  if (createPostgresContainer) {
    installDocker();

    installDockerCompose();

    postgresManager.installPostgressDaemon();

    postgresManager.startPostgresDaemon();
  }

  postgresManager.stopPostgresDaemon();

  print('Setup complete');
  print(orange('run ./run_unit_tests.dart'));
}

// void preChecks() {
//   if (!Platform.isLinux) {
//     printerr(red('Currently this script only supports linux '));
//     exit(1);
//   }

//   if (which('apt').notfound) {
//     printerr(red('Currently this script only supports apt based systems '));
//     exit(1);
//   }
// }
