import 'dart:io';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';

/// Packages a plugin directory into a deterministic .swayveplugin bundle.
Future<void> main(List<String> arguments) async {
  exitCode = await runPackage(arguments);
}
