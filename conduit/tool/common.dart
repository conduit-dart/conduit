import 'package:dcli/dcli.dart';

/// Docker functions
void installDocker() {
  if (which('docker').found) {
    print('Using an existing docker install.');
    return;
  }

  'apt --assume-yes install dockerd'.start(privileged: true);
}

/// Docker-Compose functions
void installDockerCompose() {
  if (which('docker-compose').found) {
    print('Using an existing docker-compose install.');
    return;
  }

  'apt --assume-yes install docker-compose'.start(privileged: true);
}

/// Postgres functions
void installPostgressDaemon() {
  if (isPostgresDaemonInstalled()) {
    print('Using existing postgress daemon.');
    return;
  }

  print('Installing postgres docker image');
  'docker pull postgres'.run;
}

void installPostgresClient() {
  if (isPostgresClientInstalled()) {
    print('Using existing postgress client.');
    return;
  }

  print('Installing postgres client');
  'apt  --assume-yes install postgresql-client'.start(privileged: true);
}

bool isPostgresClientInstalled() => which('psql').found;

void startPostgresDaemon() {
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
  var images = 'docker images'.toList(skipLines: 1);

  for (var image in images) {
    image = image.replaceAll('  ', ' ');
    var parts = image.split(' ');
    if (parts.isNotEmpty && parts[0] == 'postgres') {
      found = true;
      break;
    }
  }
  return found;
}
