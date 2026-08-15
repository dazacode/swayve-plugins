import 'dart:io';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

/// Small facts about the tools themselves that are easy to let rot.
void main() {
  test('kToolsVersion matches the version in pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      match!.group(1),
      kToolsVersion,
      reason: 'the generator string written into every bundle would be wrong',
    );
  });

  test('the package is not publishable to pub.dev', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('publish_to: none'),
    );
  });

  test('the lint baseline is importable and enables the contract rules', () {
    final String options = File('analysis_options.yaml').readAsStringSync();
    expect(options, contains('include: package:lints/recommended.yaml'));
    for (final String rule in <String>[
      'always_declare_return_types',
      'avoid_print',
      'prefer_final_locals',
      'require_trailing_commas',
      'unawaited_futures',
    ]) {
      expect(options, contains(rule), reason: rule);
    }
  });

  group('JSON source locations', () {
    test('points at the line a nested field is on', () {
      final JsonSource source = JsonSource.parse('''
{
  "a": 1,
  "b": {
    "c": [
      "x",
      "y"
    ]
  }
}
''');
      expect(source.lineFor('/a'), 2);
      expect(source.lineFor('/b'), 3);
      expect(source.lineFor('/b/c'), 4);
      expect(source.lineFor('/b/c/1'), 6);
    });

    test('falls back to the nearest ancestor it knows', () {
      final JsonSource source = JsonSource.parse('{\n  "a": {}\n}');
      expect(source.nearestLineFor('/a/missing/deeper'), 2);
      expect(source.nearestLineFor('/nothing'), 1);
    });

    test('escapes pointer segments the way RFC 6901 says', () {
      expect(escapePointerSegment('a/b'), 'a~1b');
      expect(escapePointerSegment('a~b'), 'a~0b');
      expect(joinPointer('/x', 'a/b'), '/x/a~1b');
    });

    test('reports the position of broken JSON', () {
      expect(
        () => JsonSource.parse('{\n  "a": ,\n}'),
        throwsA(
          isA<JsonSyntaxError>()
              .having((JsonSyntaxError e) => e.line, 'line', 2),
        ),
      );
    });
  });

  group('path safety', () {
    test('names every problem with a relative path', () {
      expect(pathProblems('assets/icon.svg'), isEmpty);
      expect(pathProblems(''), <PathProblem>[PathProblem.empty]);
      expect(pathProblems('/etc/passwd'), contains(PathProblem.absolute));
      expect(pathProblems('a/../b'), contains(PathProblem.parentTraversal));
      expect(pathProblems(r'a\b'), contains(PathProblem.backslash));
      expect(pathProblems('C:/x'), contains(PathProblem.driveLetter));
      expect(
        pathProblems('a${String.fromCharCode(0)}b'),
        contains(PathProblem.controlCharacter),
      );
    });

    test('canonicalises an archive path without resolving traversal', () {
      expect(canonicalArchivePath('./assets//icon.svg'), 'assets/icon.svg');
      expect(canonicalArchivePath('assets/icon.svg'), 'assets/icon.svg');
    });
  });

  test('bundle paths sort byte-wise, not by UTF-16 code unit', () {
    final List<String> paths = <String>['\u{1f600}.txt', '\ufb00.txt']..sort(
        compareBundlePaths,
      );
    // U+FB00 encodes to EF BB 80; U+1F600 encodes to F0 9F 98 80.
    expect(paths.first, '\ufb00.txt');
    expect(
      <String>['\u{1f600}.txt', '\ufb00.txt']..sort(),
      <String>['\u{1f600}.txt', '\ufb00.txt'],
      reason:
          'String.compareTo disagrees, which is exactly why we do not use it',
    );
  });
}
