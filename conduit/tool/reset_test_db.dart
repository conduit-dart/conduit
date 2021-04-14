#! /usr/bin/env dcli

import 'package:dcli/dcli.dart';

/// Used to reset the test database.
///
/// You shouldn't normally need to run this script as when a test run completes
/// normally, the database is droped when the docker container is shutdown.
///
/// If the tests aborted and left the container running this script will
/// shutdown the container and re-run the setup_unit_test script.
///
void main(List<String> args) {
  print('Shutting down Postgres docker container');
  'docker-compose down'.start(
      workingDirectory: join(DartProject.current.pathToProjectRoot, 'tool'));

  // var images =
  //     'docker images'.toList().where((line) => line.startsWith('postgres'));

  // for (var image in images) {
  //   image = image.replaceAll(RegExp(r'\s+'), ' ');

  //   var parts = image.split(' ');

  //   if (parts.isEmpty) {
  //     continue;
  //   }

  //   final name = parts[0];
  //   final tag = parts[1];
  //   final id = parts[2];

  //   if (confirm('Delete docker image: $name $tag $id')) {
  //     'docker image rm $id'.run;
  //   }

  './setup_unit_tests.dart'.start(
      workingDirectory: join(DartProject.current.pathToProjectRoot, 'tool'));
}
