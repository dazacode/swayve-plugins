/// The version of `swayve_plugin_tools`.
///
/// Written into every bundle's `integrity.json` as `generator`, so a bundle can
/// always say which build produced it. `test/tool_version_test.dart` keeps this
/// equal to the version in `pubspec.yaml`.
const String kToolsVersion = '1.0.0';

/// The `generator` string written into `integrity.json`.
const String kGeneratorId = 'swayve_plugin_tools/$kToolsVersion';
