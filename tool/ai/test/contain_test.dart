@TestOn('linux')
library;

import 'dart:io';

import 'package:test/test.dart';

/// tool/ai/contain.sh, run the way the workflows run it. Reaping is turned
/// off (CONTAIN_REAP=0): it kills every new process the uid can see, which
/// would include the test runner's own. The workflows rely on it only inside
/// the runner's job container.
void main() {
  final script = File('contain.sh').absolute.path;
  late Directory tmp;
  late File envFile;
  late File pathFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('contain_test');
    envFile = File('${tmp.path}/env')..writeAsStringSync('KEEP=1\n');
    pathFile = File('${tmp.path}/path')..writeAsStringSync('');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProcessResult> contain(List<String> args) => Process.run(
    script,
    args,
    environment: {
      'CONTAIN_REAP': '0',
      'GITHUB_ENV': envFile.path,
      'GITHUB_PATH': pathFile.path,
      'GH_TOKEN': 'app-token',
      'CLAUDE_CODE_OAUTH_TOKEN': 'oauth-token',
    },
  );

  test('runs the command without secrets or workflow command files', () async {
    final r = await contain([
      'bash',
      '-c',
      r'echo "${GH_TOKEN:-none} ${CLAUDE_CODE_OAUTH_TOKEN:-none} ${GITHUB_ENV:-none}"',
    ]);
    expect(r.exitCode, 0);
    expect(r.stdout, 'none none none\n');
  });

  test('--keep passes one secret through', () async {
    final r = await contain([
      '--keep',
      'CLAUDE_CODE_OAUTH_TOKEN',
      'bash',
      '-c',
      r'echo "${GH_TOKEN:-none} ${CLAUDE_CODE_OAUTH_TOKEN:-none}"',
    ]);
    expect(r.stdout, 'none oauth-token\n');
  });

  test(
    'undoes writes to workflow command files through a known path',
    () async {
      final r = await contain([
        'bash',
        '-c',
        'echo LD_PRELOAD=/tmp/x.so >> ${envFile.path}; '
            'echo /evil >> ${pathFile.path}',
      ]);
      expect(r.exitCode, 0);
      expect(envFile.readAsStringSync(), 'KEEP=1\n');
      expect(pathFile.readAsStringSync(), isEmpty);
    },
  );

  test("returns the command's exit status", () async {
    final r = await contain(['bash', '-c', 'exit 7']);
    expect(r.exitCode, 7);
  });

  test('needs a command', () async {
    final r = await contain([]);
    expect(r.exitCode, 2);
  });
}
