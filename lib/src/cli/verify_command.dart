import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../diagnostics.dart';
import '../verifier.dart';
import 'cli.dart';

/// The tool name used in `--json` output and error lines.
const String kVerifyToolName = 'verify_package';

const String _usage = 'Usage: dart run tools/verify_package.dart '
    '<bundle.swayveplugin> [--pubkey <path|base64>] [options]\n\n'
    'Checks a bundle the way a host must before unpacking it: extraction '
    'safety first, then integrity, then signature.';

/// Runs `verify_package` with [arguments] and returns its exit code.
Future<int> runVerify(List<String> arguments) {
  final ArgParser parser = baseParser()
    ..addOption(
      'pubkey',
      help: 'Public key the bundle must be signed by: a file or base64.',
    )
    ..addOption(
      'dest',
      help: 'Destination directory to test path containment against.',
    )
    ..addFlag(
      'require-signature',
      negatable: false,
      help: 'Fail an unsigned bundle instead of noting it.',
    );

  return runCli(
    tool: kVerifyToolName,
    usage: _usage,
    parser: parser,
    arguments: arguments,
    body: (ArgResults args, CliOptions options) async {
      if (args.rest.length != 1) {
        throw CliUsageError(
          args.rest.isEmpty
              ? 'name exactly one .swayveplugin bundle to verify'
              : 'verify one bundle at a time; got ${args.rest.length} paths',
        );
      }
      final String path = args.rest.single;
      final File file = File(path);
      if (!file.existsSync()) {
        throw CliUsageError('no such bundle: $path');
      }

      final List<int>? publicKey = _readPublicKey(args.option('pubkey'));
      final Uint8List bytes = file.readAsBytesSync();
      final BundleVerifier verifier = BundleVerifier(
        destinationRoot: args.option('dest') ?? kDefaultDestinationRoot,
        expectedPublicKey: publicKey,
        requireSignature: args.flag('require-signature'),
      );
      return <Report>[
        await verifier.verify(
          bytes,
          target: path,
          fileName: p.basename(path),
        ),
      ];
    },
  );
}

List<int>? _readPublicKey(String? value) {
  if (value == null) {
    return null;
  }
  final File file = File(value);
  final String text = file.existsSync() ? file.readAsStringSync() : value;
  final String compact = text.replaceAll(RegExp(r'\s'), '');
  final List<int> decoded;
  try {
    decoded = base64.decode(base64.normalize(compact));
  } on FormatException {
    throw CliUsageError('--pubkey is neither a readable file nor base64');
  }
  if (decoded.length != 32) {
    throw CliUsageError(
      '--pubkey decodes to ${decoded.length} bytes; an ed25519 public key '
      'is 32',
    );
  }
  return decoded;
}
