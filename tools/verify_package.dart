import 'dart:io';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';

/// Verifies a .swayveplugin bundle before anyone unpacks it.
Future<void> main(List<String> arguments) async {
  exitCode = await runVerify(arguments);
}
