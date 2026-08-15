/// Validation, packaging and verification for Swayve plugins.
///
/// `tools/validate_plugin.dart`, `tools/package_plugin.dart` and
/// `tools/verify_package.dart` are thin entry points over this library, so
/// everything they do can also be driven from a test or from another tool.
library;

export 'src/bundle.dart';
export 'src/cli/cli.dart';
export 'src/cli/package_command.dart';
export 'src/cli/validate_command.dart';
export 'src/cli/verify_command.dart';
export 'src/diagnostics.dart';
export 'src/json_source.dart';
export 'src/manifest.dart';
export 'src/manifest_rules.dart';
export 'src/packager.dart';
export 'src/safe_path.dart';
export 'src/schema_spec.dart';
export 'src/semver.dart';
export 'src/signing.dart';
export 'src/structural_validator.dart';
export 'src/tool_version.dart';
export 'src/validator.dart';
export 'src/verifier.dart';
export 'src/vocabulary.dart';
