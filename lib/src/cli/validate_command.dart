import 'package:args/args.dart';

import '../validator.dart';
import 'cli.dart';

/// The tool name used in `--json` output and error lines.
const String kValidateToolName = 'validate_plugin';

const String _usage = 'Usage: dart run tools/validate_plugin.dart '
    '<plugin directory>... [options]\n'
    '       dart run tools/validate_plugin.dart --all [options]\n\n'
    "Checks a plugin's plugin.json against the published schema and every "
    'cross-field rule.';

/// Runs `validate_plugin` with [arguments] and returns its exit code.
Future<int> runValidate(List<String> arguments) {
  final ArgParser parser = baseParser()
    ..addFlag(
      'all',
      negatable: false,
      help: 'Validate every plugin under the plugins root.',
    )
    ..addOption(
      'plugins-root',
      defaultsTo: 'plugins',
      help: 'Directory --all scans.',
    );

  return runCli(
    tool: kValidateToolName,
    usage: _usage,
    parser: parser,
    arguments: arguments,
    body: (ArgResults args, CliOptions options) async {
      final List<String> targets = _targets(args);
      return targets
          .map((String dir) => validatePluginDirectory(dir).report)
          .toList(growable: false);
    },
  );
}

List<String> _targets(ArgResults args) {
  final bool all = args.flag('all');
  final List<String> positional = args.rest;
  if (all && positional.isNotEmpty) {
    throw const CliUsageError(
      '--all takes no plugin directories; pass one or the other',
    );
  }
  if (all) {
    final String root = args.option('plugins-root') ?? 'plugins';
    final List<String> found = discoverPluginDirectories(root);
    if (found.isEmpty) {
      throw CliUsageError('no plugins found under $root');
    }
    return found;
  }
  if (positional.isEmpty) {
    throw const CliUsageError('name a plugin directory, or pass --all');
  }
  return positional;
}
