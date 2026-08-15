import 'dart:io';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';

/// Validates one or more plugin directories against the manifest contract.
Future<void> main(List<String> arguments) async {
  exitCode = await runValidate(arguments);
}
