import 'dart:io';

import 'package:path/path.dart' as p;

import 'diagnostics.dart';
import 'json_source.dart';
import 'manifest.dart';
import 'manifest_rules.dart';
import 'schema_spec.dart';
import 'structural_validator.dart';

/// The manifest filename, everywhere.
const String kManifestFileName = 'plugin.json';

/// The result of reading and checking one manifest.
final class ManifestValidation {
  /// Creates a validation result.
  const ManifestValidation(this.report, this.manifest);

  /// Everything the checks found.
  final Report report;

  /// The manifest, empty if it could not be decoded.
  final PluginManifest manifest;
}

/// Checks the manifest [text] and returns what it found.
///
/// [directoryName] enables rule 7; leave it `null` when the manifest did not
/// come from a plugin directory. [source] is the filename diagnostics point at.
ManifestValidation validateManifestText(
  String text, {
  required String target,
  String? directoryName,
  String source = kManifestFileName,
}) {
  final JsonSource parsed;
  try {
    parsed = JsonSource.parse(text);
  } on JsonSyntaxError catch (e) {
    return ManifestValidation(
      Report(target, <Diagnostic>[
        Diagnostic.error(
          DiagnosticCodes.manifestMalformedJson,
          '$source is not valid JSON: ${e.message}',
          source: source,
          line: e.line,
        ),
      ]),
      const PluginManifest(<String, Object?>{}),
    );
  }

  final Object? value = parsed.value;
  if (value is! Map<String, Object?>) {
    return ManifestValidation(
      Report(target, <Diagnostic>[
        Diagnostic.error(
          DiagnosticCodes.manifestNotObject,
          '$source must contain a JSON object at the top level, '
          'found ${jsonTypeOf(value)}',
          source: source,
          line: 1,
        ),
      ]),
      const PluginManifest(<String, Object?>{}),
    );
  }

  final DiagnosticSink sink = DiagnosticSink();
  StructuralValidator(sink).check(value, manifestSpec);
  final PluginManifest manifest = PluginManifest(value);
  ManifestRules(manifest, sink, directoryName: directoryName).runAll();

  final List<Diagnostic> located = sink.diagnostics
      .map(
        (Diagnostic d) => d.withLocation(
          source: source,
          line: parsed.nearestLineFor(d.pointer),
        ),
      )
      .toList(growable: false);
  return ManifestValidation(Report(target, located), manifest);
}

/// Reads `plugin.json` from [directory] and checks it.
///
/// [target] defaults to [directory] as written, so the human output echoes
/// exactly what was typed on the command line.
ManifestValidation validatePluginDirectory(String directory, {String? target}) {
  final String shown = target ?? directory;
  final Directory dir = Directory(directory);
  if (!dir.existsSync()) {
    return ManifestValidation(
      Report(shown, <Diagnostic>[
        Diagnostic.error(
          DiagnosticCodes.manifestNotFound,
          'no such plugin directory: $directory',
        ),
      ]),
      const PluginManifest(<String, Object?>{}),
    );
  }
  final File manifestFile = File(p.join(directory, kManifestFileName));
  if (!manifestFile.existsSync()) {
    return ManifestValidation(
      Report(shown, <Diagnostic>[
        Diagnostic.error(
          DiagnosticCodes.manifestNotFound,
          'no $kManifestFileName in $directory',
        ),
      ]),
      const PluginManifest(<String, Object?>{}),
    );
  }
  final String text;
  try {
    text = manifestFile.readAsStringSync();
  } on FileSystemException catch (e) {
    return ManifestValidation(
      Report(shown, <Diagnostic>[
        Diagnostic.error(
          DiagnosticCodes.manifestUnreadable,
          'could not read $kManifestFileName: ${e.message}',
          source: kManifestFileName,
        ),
      ]),
      const PluginManifest(<String, Object?>{}),
    );
  }
  return validateManifestText(
    text,
    target: shown,
    directoryName: p.basename(p.normalize(p.absolute(directory))),
  );
}

/// Every immediate subdirectory of [pluginsRoot] that holds a `plugin.json`,
/// sorted by name so `--all` output is stable.
List<String> discoverPluginDirectories(String pluginsRoot) {
  final Directory root = Directory(pluginsRoot);
  if (!root.existsSync()) {
    return const <String>[];
  }
  final List<String> found = <String>[];
  for (final FileSystemEntity entity in root.listSync(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    if (File(p.join(entity.path, kManifestFileName)).existsSync()) {
      // Forward slashes whatever the platform: these strings are echoed back as
      // the target of every diagnostic and a mix of separators is just noise.
      found.add(entity.path.replaceAll(r'\', '/'));
    }
  }
  found.sort();
  return found;
}
