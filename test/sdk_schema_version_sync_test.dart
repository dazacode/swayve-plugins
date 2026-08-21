import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

/// [kManifestSchemaVersion] (this package, used by the validator/CLI) and
/// [kSwayveManifestSchemaVersion] (`swayve_plugin_sdk`, used by every host
/// app's own runtime compatibility check) are two independently-defined
/// copies of "the schema version this build understands."
///
/// A host app checks a fetched manifest against its own compiled copy of
/// `kSwayveManifestSchemaVersion` — not against this package, which host apps
/// don't runtime-depend on at all. Nothing but this test keeps the two
/// numbers equal, and they drifted silently once already (`personal_library`
/// bumped this package's constant without touching the SDK's, so every host
/// app rejected a `personal_library`-capable manifest as "a version of the
/// manifest format this app does not understand" until this test existed).
void main() {
  test('the validator and the SDK agree on the current schema version', () {
    expect(
      kManifestSchemaVersion,
      kSwayveManifestSchemaVersion,
      reason:
          'lib/src/vocabulary.dart\'s kManifestSchemaVersion and '
          'packages/swayve_plugin_sdk/lib/src/constants.dart\'s '
          'kSwayveManifestSchemaVersion must be bumped together — see this '
          'file\'s doc comment for what happens when they drift.',
    );
  });
}
