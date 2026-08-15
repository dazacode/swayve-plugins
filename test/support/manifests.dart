import 'dart:convert';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

/// A manifest that passes every check with nothing to say about it.
///
/// Tests start from this and change exactly the one thing under test, so a
/// failure names the rule rather than the fixture.
Map<String, Object?> cleanManifest() => <String, Object?>{
      'schemaVersion': 1,
      'id': 'com.example.plugins.demo_source',
      'name': 'Demo Source',
      'description': 'A minimal plugin used to exercise the tooling.',
      'version': '1.0.0',
      'author': <String, Object?>{'name': 'Example Co'},
      'license': 'Apache-2.0',
      'swayvePluginApi': 1,
      'minimumSwayveVersion': '0.1.0',
      'runtime': 'compiled',
      'platforms': <String>['android', 'windows'],
      'capabilities': <String>['search'],
      'permissions': <String>['network'],
      'entrypoint': 'demo_source',
      'network': <String, Object?>{
        'hosts': <String>['api.example.com'],
      },
    };

/// Encodes [manifest] the way a plugin author would write it.
String encodeManifest(Map<String, Object?> manifest) =>
    const JsonEncoder.withIndent('  ').convert(manifest);

/// Validates [manifest] and returns the report.
Report validate(
  Map<String, Object?> manifest, {
  String? directoryName,
  String target = 'fixture',
}) =>
    validateManifestText(
      encodeManifest(manifest),
      target: target,
      directoryName: directoryName,
    ).report;

/// The machine codes present in [report], in order.
List<String> codesOf(Report report) =>
    report.diagnostics.map((Diagnostic d) => d.code).toList(growable: false);

/// The single diagnostic in [report] carrying [code].
Diagnostic diagnosticFor(Report report, String code) {
  final Iterable<Diagnostic> matches =
      report.diagnostics.where((Diagnostic d) => d.code == code);
  expect(
    matches,
    hasLength(1),
    reason: 'expected exactly one $code; got ${codesOf(report)}',
  );
  return matches.single;
}
