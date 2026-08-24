/// The plugin API level implemented by this SDK.
///
/// A plugin declares the API level it targets as `swayvePluginApi` in its
/// `plugin.json`. A host refuses to load a plugin whose declared level is
/// greater than its own, and reports the mismatch as a
/// [SwayveIncompatibleApiException]. The level changes only on a breaking
/// change to the surface exported by `package:swayve_plugin_sdk`.
const int kSwayvePluginApiVersion = 1;

/// The manifest schema version this SDK understands.
///
/// A `plugin.json` whose `schemaVersion` is greater than this value is
/// rejected before any other validation runs: the host cannot safely
/// interpret a manifest whose shape it does not know. A manifest declaring an
/// older `schemaVersion` stays valid — the format only ever widens (a new
/// capability, a new optional field), so a build that understands version 2
/// still reads a version 1 manifest correctly.
const int kSwayveManifestSchemaVersion = 6;

/// The URI scheme used by [SwayveMediaId.uri].
///
/// Callers may rely on this being stable: identifiers minted by any plugin,
/// on any platform, in any Swayve version that speaks API level
/// [kSwayvePluginApiVersion], use this scheme.
const String kSwayveMediaIdScheme = 'swayve';
