import 'package:meta/meta.dart';

import 'context.dart';
import 'enums.dart';
import 'internal/equality.dart';
import 'internal/json.dart';
import 'version.dart';

/// What a plugin says about itself, in code.
///
/// Every field must agree with the plugin's `plugin.json`: the manifest is
/// what the user and the validator see, and this is what the running host
/// sees. The host may compare them and refuse to load a plugin whose code
/// and manifest disagree, because a mismatch means the permissions the user
/// approved are not the permissions the code expects.
@immutable
final class SwayvePluginIdentity {
  /// Creates an identity.
  const SwayvePluginIdentity({
    required this.id,
    required this.name,
    required this.version,
    required this.capabilities,
    this.swayvePluginApi = 1,
    this.permissions = const {},
  });

  /// The reverse-DNS plugin id, identical to the manifest's `id`.
  ///
  /// Also the `pluginId` of every `SwayveMediaId` this plugin mints.
  final String id;

  /// The human-readable name, identical to the manifest's `name`.
  ///
  /// The host shows this to the user, including in failure copy such as
  /// `"<name> — Temporarily unavailable"`.
  final String name;

  /// The plugin's own version, identical to the manifest's `version`.
  final Version version;

  /// The plugin API level this plugin was written against.
  ///
  /// The host refuses to load the plugin when this exceeds its own level,
  /// reporting `SwayveIncompatibleApiException`.
  final int swayvePluginApi;

  /// The capabilities this plugin implements.
  ///
  /// The plugin must register a provider for each one during `initialize`,
  /// and may not register a provider for a capability that is not here.
  final Set<SwayveCapability> capabilities;

  /// The permissions this plugin requires.
  ///
  /// Accessing a facility outside this set throws
  /// `SwayvePermissionDeniedException`.
  final Set<SwayvePermission> permissions;

  /// Whether this plugin declared [capability].
  bool has(SwayveCapability capability) => capabilities.contains(capability);

  /// Whether this plugin declared [permission].
  bool needs(SwayvePermission permission) => permissions.contains(permission);

  /// Returns a copy with the given fields replaced.
  SwayvePluginIdentity copyWith({
    String? id,
    String? name,
    Version? version,
    int? swayvePluginApi,
    Set<SwayveCapability>? capabilities,
    Set<SwayvePermission>? permissions,
  }) =>
      SwayvePluginIdentity(
        id: id ?? this.id,
        name: name ?? this.name,
        version: version ?? this.version,
        swayvePluginApi: swayvePluginApi ?? this.swayvePluginApi,
        capabilities: capabilities ?? this.capabilities,
        permissions: permissions ?? this.permissions,
      );

  /// The wire form, using the manifest's spelling for every enum.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'version': version.toJson(),
        'swayvePluginApi': swayvePluginApi,
        'capabilities':
            capabilities.map((capability) => capability.wireName).toList(),
        'permissions':
            permissions.map((permission) => permission.wireName).toList(),
      };

  /// Parses the wire form produced by [toJson].
  ///
  /// This accepts the same field names a `plugin.json` uses, so a host may
  /// build an identity straight from a parsed manifest.
  static SwayvePluginIdentity fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayvePluginIdentity', json);
    return SwayvePluginIdentity(
      id: reader.string('id'),
      name: reader.string('name'),
      version: reader.version('version'),
      swayvePluginApi: reader.integerOrNull('swayvePluginApi') ?? 1,
      capabilities: reader.enumSet('capabilities', SwayveCapability.fromWire),
      permissions: reader.enumSet('permissions', SwayvePermission.fromWire),
    );
  }

  @override
  String toString() => 'SwayvePluginIdentity($id $version)';

  @override
  bool operator ==(Object other) =>
      other is SwayvePluginIdentity &&
      id == other.id &&
      name == other.name &&
      version == other.version &&
      swayvePluginApi == other.swayvePluginApi &&
      deepEquals(capabilities, other.capabilities) &&
      deepEquals(permissions, other.permissions);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        version,
        swayvePluginApi,
        deepHash(capabilities),
        deepHash(permissions),
      );
}

/// The contract every Swayve plugin implements.
///
/// The lifecycle the host drives is:
/// `load → initialize → registerProviders → active → (degraded | disabled)
/// → dispose`.
///
/// What an implementer must guarantee:
/// * [identity] is cheap, synchronous and constant — it is read before
///   [initialize] and must not depend on any host facility;
/// * [initialize] returns within `SwayveTimeouts.initialize`, registering
///   every provider its declared capabilities promise, and doing no
///   speculative network work;
/// * [dispose] returns within `SwayveTimeouts.dispose`, releases every
///   resource, and does not depend on the network;
/// * neither method throws anything but a `SwayvePluginException`.
///
/// A plugin that throws or hangs in either phase moves to `degraded`: it
/// stays installed, its surfaces disappear, and the rest of Swayve is
/// unaffected (principle 7). Swayve itself works with zero plugins
/// (principle 1), so nothing here is ever on the app's critical path.
abstract interface class SwayvePlugin {
  /// What this plugin is. Must agree with its `plugin.json`.
  SwayvePluginIdentity get identity;

  /// Prepares the plugin and registers its providers.
  ///
  /// Called once, with a [context] that stays valid until [dispose]
  /// completes. Register every provider here: registration after
  /// initialization may be rejected.
  Future<void> initialize(SwayvePluginContext context);

  /// Releases everything the plugin holds.
  ///
  /// Called once. Must be safe to call after a failed [initialize], and must
  /// not throw on a second call. After it completes the plugin must make no
  /// further use of the context.
  Future<void> dispose();
}

/// The single symbol a compiled plugin exposes.
///
/// The host calls it to obtain an instance; it must be cheap, synchronous
/// and free of side effects — all real work belongs in
/// `SwayvePlugin.initialize`. The function's name must match the manifest's
/// `entrypoint`.
typedef SwayvePluginFactory = SwayvePlugin Function();
