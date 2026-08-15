import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

/// End-to-end checks of the three command lines: the exact exit codes, the
/// human output shape from CONTRACT section 9, and `--json` carrying the
/// machine codes a CI job matches on.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('swayve_cli_');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  group('exit codes', () {
    test('0 when a plugin passes', () {
      final ProcessResult result =
          _run('tools/validate_plugin.dart', <String>[_fixture]);
      expect(result.exitCode, ExitCodes.ok, reason: result.stderr.toString());
    });

    test('1 when a plugin fails', () {
      final ProcessResult result = _run(
        'tools/validate_plugin.dart',
        <String>['test/fixtures/plugins/misnamed_directory'],
      );
      expect(result.exitCode, ExitCodes.failed);
    });

    test('1 when --strict promotes a warning', () {
      final String warning = _warningOnlyPlugin(temp);
      expect(
        _run('tools/validate_plugin.dart', <String>[warning]).exitCode,
        ExitCodes.ok,
      );
      expect(
        _run('tools/validate_plugin.dart', <String>[warning, '--strict'])
            .exitCode,
        ExitCodes.failed,
      );
    });

    test('0 for a fully offline plugin, even under --strict', () {
      const String offline = 'test/fixtures/plugins/offline_catalogue';
      final ProcessResult lenient =
          _run('tools/validate_plugin.dart', <String>[offline]);
      expect(lenient.exitCode, ExitCodes.ok, reason: '${lenient.stdout}');
      expect(lenient.stdout, contains('INFO    '));
      expect(lenient.stdout, contains('usually reaches an external service'));
      expect(_lines(lenient.stdout as String).last, '0 problems');

      final ProcessResult strict =
          _run('tools/validate_plugin.dart', <String>[offline, '--strict']);
      expect(
        strict.exitCode,
        ExitCodes.ok,
        reason: '--strict must not promote an info note: ${strict.stdout}',
      );
    });

    test('2 when no target is named', () {
      final ProcessResult result =
          _run('tools/validate_plugin.dart', <String>[]);
      expect(result.exitCode, ExitCodes.badUsage);
      expect(result.stderr, contains('plugin directory'));
    });

    test('2 for an unknown flag', () {
      expect(
        _run('tools/validate_plugin.dart', <String>[_fixture, '--nope'])
            .exitCode,
        ExitCodes.badUsage,
      );
    });

    test('2 when --all is mixed with a directory', () {
      expect(
        _run('tools/validate_plugin.dart', <String>['--all', _fixture])
            .exitCode,
        ExitCodes.badUsage,
      );
    });

    test('2 when the bundle to verify does not exist', () {
      expect(
        _run('tools/verify_package.dart', <String>['nope.swayveplugin'])
            .exitCode,
        ExitCodes.badUsage,
      );
    });

    test('0 for --help on every tool', () {
      for (final String tool in <String>[
        'tools/validate_plugin.dart',
        'tools/package_plugin.dart',
        'tools/verify_package.dart',
      ]) {
        final ProcessResult result = _run(tool, <String>['--help']);
        expect(result.exitCode, ExitCodes.ok, reason: tool);
        expect(result.stdout, contains('Usage:'), reason: tool);
        expect(result.stdout, contains('--json'), reason: tool);
        expect(result.stdout, contains('--quiet'), reason: tool);
        expect(result.stdout, contains('--strict'), reason: tool);
      }
    });
  });

  group('human output', () {
    test('names the target, then the diagnostics, then the count', () {
      final ProcessResult result = _run(
        'tools/validate_plugin.dart',
        <String>['test/fixtures/plugins/misnamed_directory'],
      );
      final List<String> lines = _lines(result.stdout as String);
      expect(lines.first, 'test/fixtures/plugins/misnamed_directory');
      expect(lines[1], startsWith('  ERROR   '));
      expect(lines[1], contains('(plugin.json:'));
      expect(lines.last, '1 problem (1 error)');
    });

    test('the severity label is padded to a fixed width', () {
      expect(
        formatDiagnostic(
          const Diagnostic.error('x', 'a message'),
        ),
        'ERROR   a message',
      );
      expect(
        formatDiagnostic(const Diagnostic.warning('x', 'a message')),
        'WARNING a message',
      );
      expect(
        formatDiagnostic(const Diagnostic.info('x', 'a message')),
        'INFO    a message',
      );
    });

    test('the count line reads naturally', () {
      expect(summaryLine(0, 0), '0 problems');
      expect(summaryLine(1, 0), '1 problem (1 error)');
      expect(summaryLine(1, 1), '2 problems (1 error, 1 warning)');
      expect(summaryLine(0, 3), '3 problems (3 warnings)');
    });

    test('a clean run says so', () {
      final ProcessResult result =
          _run('tools/validate_plugin.dart', <String>[_fixture]);
      expect(_lines(result.stdout as String).last, '0 problems');
    });

    test('--quiet prints nothing for a clean run', () {
      final ProcessResult result =
          _run('tools/validate_plugin.dart', <String>[_fixture, '--quiet']);
      expect(result.stdout, isEmpty);
      expect(result.exitCode, ExitCodes.ok);
    });

    test('--quiet still prints errors', () {
      final ProcessResult result = _run(
        'tools/validate_plugin.dart',
        <String>['test/fixtures/plugins/misnamed_directory', '--quiet'],
      );
      expect(result.stdout, contains('ERROR'));
      expect(result.stdout, isNot(contains('problem')));
    });
  });

  group('--json', () {
    test('is valid JSON carrying the machine codes', () {
      final ProcessResult result = _run(
        'tools/validate_plugin.dart',
        <String>['test/fixtures/plugins/misnamed_directory', '--json'],
      );
      final Map<String, Object?> document =
          jsonDecode(result.stdout as String)! as Map<String, Object?>;
      expect(document['tool'], 'validate_plugin');
      expect(document['toolVersion'], kToolsVersion);
      expect(document['ok'], isFalse);
      expect(document['strict'], isFalse);

      final List<Object?> results = document['results']! as List<Object?>;
      final Map<String, Object?> first = results.first! as Map<String, Object?>;
      expect(first['target'], 'test/fixtures/plugins/misnamed_directory');
      final List<Object?> diagnostics = first['diagnostics']! as List<Object?>;
      final Set<Object?> codes = diagnostics
          .map((Object? d) => (d! as Map<String, Object?>)['code'])
          .toSet();
      expect(codes, contains(DiagnosticCodes.directoryNameMismatch));

      final Map<String, Object?> diagnostic =
          diagnostics.first! as Map<String, Object?>;
      expect(
        diagnostic.keys,
        containsAll(<String>['code', 'severity', 'message', 'pointer']),
      );
      expect(
        diagnostic['severity'],
        isIn(<String>['error', 'warning', 'info']),
      );
    });

    test('reports bad usage as JSON too, still with exit code 2', () {
      final ProcessResult result =
          _run('tools/validate_plugin.dart', <String>['--json']);
      expect(result.exitCode, ExitCodes.badUsage);
      final Map<String, Object?> document =
          jsonDecode(result.stdout as String)! as Map<String, Object?>;
      expect(document['ok'], isFalse);
      final Map<String, Object?> error =
          document['error']! as Map<String, Object?>;
      expect(error['code'], DiagnosticCodes.badUsage);
    });

    test('a clean run is JSON with ok true and no diagnostics', () {
      final ProcessResult result =
          _run('tools/validate_plugin.dart', <String>[_fixture, '--json']);
      final Map<String, Object?> document =
          jsonDecode(result.stdout as String)! as Map<String, Object?>;
      expect(document['ok'], isTrue);
      expect(
        ((document['results']! as List<Object?>).first!
            as Map<String, Object?>)['diagnostics'],
        isEmpty,
      );
    });
  });

  group('package then verify', () {
    test('the round trip works from the command line', () {
      final String out = p.join(temp.path, 'dist');
      final ProcessResult packaged = _run(
        'tools/package_plugin.dart',
        <String>[_fixture, '--out', out],
      );
      expect(packaged.exitCode, ExitCodes.ok, reason: '${packaged.stderr}');
      expect(packaged.stdout, contains('wrote '));

      final String bundle = p.join(out, 'demo_source-1.0.0.swayveplugin');
      expect(File(bundle).existsSync(), isTrue);
      expect(
        File(p.join(out, 'demo_source-1.0.0.sha256')).existsSync(),
        isTrue,
      );

      final ProcessResult verified =
          _run('tools/verify_package.dart', <String>[bundle]);
      expect(verified.exitCode, ExitCodes.ok, reason: '${verified.stderr}');
      expect(verified.stdout, contains('INFO    '));
      expect(_lines(verified.stdout as String).last, '0 problems');
    });

    test('packaging emits machine-readable artifact paths with --json', () {
      final String out = p.join(temp.path, 'dist');
      final ProcessResult packaged = _run(
        'tools/package_plugin.dart',
        <String>[_fixture, '--out', out, '--json'],
      );
      final Map<String, Object?> document =
          jsonDecode(packaged.stdout as String)! as Map<String, Object?>;
      final Map<String, Object?> first = (document['results']! as List<Object?>)
          .first! as Map<String, Object?>;
      expect(first['artifacts'], hasLength(2));
      expect(first['signed'], isFalse);
      expect(first['digest'], isA<String>());
    });

    test('a plugin that fails validation writes nothing', () {
      final String out = p.join(temp.path, 'dist');
      final ProcessResult packaged = _run(
        'tools/package_plugin.dart',
        <String>['test/fixtures/plugins/no_licenses', '--out', out],
      );
      expect(packaged.exitCode, ExitCodes.failed);
      expect(Directory(out).existsSync(), isFalse);
    });

    test('--key signs the bundle and --pubkey checks it', () {
      final String keyPath = p.join(temp.path, 'ed25519.key');
      final List<int> seed =
          List<int>.generate(32, (int i) => (i * 5 + 1) & 255);
      File(keyPath).writeAsStringSync('${base64.encode(seed)}\n');

      final String out = p.join(temp.path, 'dist');
      final ProcessResult packaged = _run(
        'tools/package_plugin.dart',
        <String>[_fixture, '--out', out, '--key', keyPath, '--json'],
      );
      expect(packaged.exitCode, ExitCodes.ok, reason: '${packaged.stderr}');
      final Map<String, Object?> document =
          jsonDecode(packaged.stdout as String)! as Map<String, Object?>;
      expect(
        ((document['results']! as List<Object?>).first!
            as Map<String, Object?>)['signed'],
        isTrue,
      );

      final String bundle = p.join(out, 'demo_source-1.0.0.swayveplugin');
      expect(
        _run('tools/verify_package.dart', <String>[bundle]).exitCode,
        ExitCodes.ok,
      );

      final ProcessResult wrongKey = _run(
        'tools/verify_package.dart',
        <String>[
          bundle,
          '--pubkey',
          base64.encode(List<int>.filled(32, 1)),
        ],
      );
      expect(wrongKey.exitCode, ExitCodes.failed);
      expect(wrongKey.stdout, contains('signed by key'));
    });

    test('a key file that is not a key is a clear failure', () {
      final String keyPath = p.join(temp.path, 'bad.key');
      File(keyPath).writeAsStringSync('this is not a key');
      final ProcessResult result = _run(
        'tools/package_plugin.dart',
        <String>[
          _fixture,
          '--out',
          p.join(temp.path, 'dist'),
          '--key',
          keyPath,
        ],
      );
      expect(result.exitCode, ExitCodes.failed);
      expect(result.stdout, contains('ERROR'));
    });

    test('a missing key file is bad usage, not a crash', () {
      expect(
        _run(
          'tools/package_plugin.dart',
          <String>[_fixture, '--key', p.join(temp.path, 'absent.key')],
        ).exitCode,
        ExitCodes.badUsage,
      );
    });
  });

  group('--all', () {
    test('scans a plugins root and reports each plugin', () {
      final ProcessResult result = _run(
        'tools/validate_plugin.dart',
        <String>['--all', '--plugins-root', 'test/fixtures/plugins', '--json'],
      );
      final Map<String, Object?> document =
          jsonDecode(result.stdout as String)! as Map<String, Object?>;
      final List<Object?> results = document['results']! as List<Object?>;
      expect(results, hasLength(4));
      expect(document['ok'], isFalse); // misnamed_directory fails
    });

    test('an empty plugins root is bad usage', () {
      expect(
        _run(
          'tools/validate_plugin.dart',
          <String>['--all', '--plugins-root', temp.path],
        ).exitCode,
        ExitCodes.badUsage,
      );
    });
  });
}

const String _fixture = 'test/fixtures/plugins/demo_source';

ProcessResult _run(String tool, List<String> arguments) => Process.runSync(
      Platform.resolvedExecutable,
      <String>['run', tool, ...arguments],
      workingDirectory: Directory.current.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

List<String> _lines(String output) => output
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((String line) => line.isNotEmpty)
    .toList(growable: false);

/// A copy of the fixture whose only problem is an over-permissioned manifest.
String _warningOnlyPlugin(Directory temp) {
  final String destination = p.join(temp.path, 'demo_source');
  Directory(destination).createSync(recursive: true);
  final Map<String, Object?> manifest = jsonDecode(
    File(p.join(_fixture, 'plugin.json')).readAsStringSync(),
  )! as Map<String, Object?>;
  manifest['permissions'] = <String>['network', 'webview'];
  File(p.join(destination, 'plugin.json'))
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  return destination;
}
