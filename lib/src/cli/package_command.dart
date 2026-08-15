import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';

import '../diagnostics.dart';
import '../packager.dart';
import '../signing.dart';
import 'cli.dart';

/// The tool name used in `--json` output and error lines.
const String kPackageToolName = 'package_plugin';

const String _usage = 'Usage: dart run tools/package_plugin.dart '
    '<plugin directory> [--out dist] [--key path/to/ed25519.key] [options]\n\n'
    'Validates the plugin, then writes a deterministic .swayveplugin bundle '
    'and its .sha256 sidecar. Nothing is written for a plugin that does not '
    'pass validation.';

/// Runs `package_plugin` with [arguments] and returns its exit code.
Future<int> runPackage(List<String> arguments) {
  final ArgParser parser = baseParser()
    ..addOption(
      'out',
      defaultsTo: 'dist',
      help: 'Directory the bundle is written into.',
    )
    ..addOption(
      'key',
      help: 'ed25519 private key seed used to sign the bundle digest.',
    );

  final List<String> written = <String>[];

  return runCli(
    tool: kPackageToolName,
    usage: _usage,
    parser: parser,
    arguments: arguments,
    epilogue: () =>
        written.map((String path) => 'wrote $path').toList(growable: false),
    body: (ArgResults args, CliOptions options) async {
      if (args.rest.length != 1) {
        throw CliUsageError(
          args.rest.isEmpty
              ? 'name exactly one plugin directory to package'
              : 'package one plugin at a time; got ${args.rest.length} paths',
        );
      }
      final String directory = args.rest.single;
      final String outputDirectory = args.option('out') ?? 'dist';
      final String? keyPath = args.option('key');

      Uint8List? seed;
      if (keyPath != null) {
        if (!kSigningAvailable) {
          throw const CliUsageError(
            'signing unavailable in this build: --key cannot be honoured, and '
            'this tool will not pretend a bundle is signed when it is not',
          );
        }
        final File keyFile = File(keyPath);
        if (!keyFile.existsSync()) {
          throw CliUsageError('no such key file: $keyPath');
        }
        try {
          seed = parseEd25519Seed(keyFile.readAsBytesSync());
        } on SigningKeyError catch (e) {
          return <Report>[
            Report(directory, <Diagnostic>[
              Diagnostic.error(
                DiagnosticCodes.signingKeyInvalid,
                'could not use $keyPath: ${e.message}',
              ),
            ]),
          ];
        }
      }

      final BuiltBundle built = await const Packager().build(
        directory,
        signingSeed: seed,
        strict: options.strict,
      );
      final Report report = built.report;
      if (built.bytes == null) {
        return <Report>[report];
      }

      written.addAll(const Packager().writeBundle(built, outputDirectory));
      report.details['artifacts'] = List<String>.of(written);
      report.details['digest'] = built.digest;
      report.details['signed'] = built.signed;
      return <Report>[report];
    },
  );
}
