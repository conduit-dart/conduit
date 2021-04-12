#! /usr/bin/env dcli

import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart';

/// dcli script generated by:
/// dcli create reset_test_db.dart
///
/// See
/// https://pub.dev/packages/dcli#-installing-tab-
///
/// For details on installing dcli.
///

void main(List<String> args) {
  print('Shutting down Postgres docker container');
  'docker-compose down'.run;

  final images =
      'docker images'.toList().where((line) => line.startsWith('postgres'));

  for (var image in images) {
    image = image.replaceAll('  ', ' ');
    final parts = image.split(' ');

    if (parts.isEmpty) continue;

    final name = parts[0];
    final tag = parts[1];
    final id = parts[2];

    if (confirm('Delete docker image $name $tag $id')) {
      'docker images rm $id'.run;
    }
  }
}
