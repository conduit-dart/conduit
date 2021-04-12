import 'package:dcli/dcli.dart';

/// Docker functions
void installDocker() {
  if (which('docker').found) {
    // ignore: avoid_print
    print('Using an existing docker install.');
    return;
  }

  'apt --assume-yes install dockerd'.start(privileged: true);
}

/// Docker-Compose functions
void installDockerCompose() {
  if (which('docker-compose').found) {
    // ignore: avoid_print
    print('Using an existing docker-compose install.');
    return;
  }

  'apt --assume-yes install docker-compose'.start(privileged: true);
}

/// Postgres functions
void installPostgressDaemon() {
  if (isPostgresDaemonInstalled()) {
    // ignore: avoid_print
    print('Using existing postgress daemon.');
    return;
  }

  // ignore: avoid_print
  print('Installing postgres docker image');
  'docker pull postgres'.run;
}

void installPostgresClient() {
  if (isPostgresClientInstalled()) {
    // ignore: avoid_print
    print('Using existing postgress client.');
    return;
  }

  // ignore: avoid_print
  print('Installing postgres client');
  'apt  --assume-yes install postgresql-client'.start(privileged: true);
}

bool isPostgresClientInstalled() => which('psql').found;

void startPostgresDaemon() {
  // ignore: avoid_print
  print('Staring docker postgres image');
  'docker-compose up -d'.run;
}

void configurePostgress(String pathToProgressDb) {
  if (!exists(pathToProgressDb)) {
    createDir(pathToProgressDb, recursive: true);
  }

  /// create
  /// database: dart_test
  /// user: dart
  /// password: dart
  // "psql --host=localhost --port=5432 -c 'create user dart with createdb;' -U postgres"
  //     .run;
  // '''psql --host=localhost --port=5432 -c 'alter user dart with password "dart";' -U postgres'''
  //     .run;
  // "psql ---host=localhost -port=5432 -c 'create database dart_test;' -U postgres"
  //     .run;
  env['PGPASSWORD'] = '34achfAdce';
  "psql --host=localhost --port=5432 -c 'grant all on database conduit_test_db to conduit_test_user;' -U conduit_test_user conduit_test_db"
      .run;
}

bool isPostgresDaemonInstalled() {
  bool found = false;
  final images = 'docker images'.toList(skipLines: 1);

  for (var image in images) {
    image = image.replaceAll('  ', ' ');
    final parts = image.split(' ');
    if (parts.isNotEmpty && parts[0] == 'postgres') {
      found = true;
      break;
    }
  }
  return found;
}
