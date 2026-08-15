/// The manifest schema version this build of the tools implements.
const int kManifestSchemaVersion = 1;

/// The SDK major API level this build of the tools implements.
const int kSwayvePluginApiVersion = 1;

/// Reverse-DNS prefix reserved for plugins published by Swayve itself.
const String kFirstPartyIdPrefix = 'app.swayve.plugins.';

/// The author name a first-party plugin must carry.
const String kFirstPartyAuthorName = 'Swayve';

/// The closed capability vocabulary, in schema order.
///
/// Each entry maps one-to-one onto a provider interface in the SDK. Adding one
/// is a schema change and lands together with docs, SDK and validator.
const List<String> kCapabilities = <String>[
  'search',
  'catalog',
  'streaming',
  'metadata',
  'lyrics',
  'scrobbling',
  'authentication',
  'webview',
  'artwork',
  'playlist_read',
];

/// The closed permission vocabulary, in schema order.
const List<String> kPermissions = <String>[
  'network',
  'webview',
  'external_auth',
  'local_plugin_storage',
  'clipboard',
];

/// Platforms a plugin may declare.
const List<String> kPlatforms = <String>[
  'android',
  'ios',
  'windows',
  'macos',
  'linux',
];

/// How a plugin reaches the device.
const List<String> kRuntimes = <String>['compiled', 'bundled'];

/// Setting descriptor types.
const List<String> kSettingTypes = <String>[
  'string',
  'bool',
  'int',
  'select',
  'secret',
];

/// Capability to the permission it is structurally unusable without.
///
/// These two are not heuristics. A `webview` capability is the ability to ask
/// the host to render a web view, which is exactly what the `webview`
/// permission grants; an `authentication` capability is a host-mediated auth
/// flow, which is exactly what `external_auth` grants. Declaring either
/// capability without its permission describes a plugin that cannot do the
/// thing it says it does, so it is an error.
const Map<String, String> kCapabilityRequiredPermission = <String, String>{
  'webview': 'webview',
  'authentication': 'external_auth',
};

/// Capabilities that usually, but not necessarily, reach an external service.
///
/// A plugin can serve any of these from data it already has: a bundled
/// catalogue, files the host already holds, a local index. Whether it opens a
/// socket is not decidable from the manifest, so the absence of the `network`
/// permission alongside one of these is a note, never a failure.
const Set<String> kNetworkExpectingCapabilities = <String>{
  'search',
  'catalog',
  'streaming',
  'metadata',
  'lyrics',
  'scrobbling',
  'artwork',
  'playlist_read',
};

/// The permissions that [capabilities] justify holding.
///
/// Used by the over-permission check: a permission in this set is one the
/// plugin has a declared reason to hold, whether that reason is structural
/// (see [kCapabilityRequiredPermission]) or merely likely (see
/// [kNetworkExpectingCapabilities]). Over-declaration is the direction that
/// costs a user trust, so this set is generous on purpose.
Set<String> permissionsJustifiedBy(Iterable<String> capabilities) {
  final Set<String> justified = <String>{};
  for (final String capability in capabilities) {
    final String? required = kCapabilityRequiredPermission[capability];
    if (required != null) {
      justified.add(required);
    }
    if (kNetworkExpectingCapabilities.contains(capability)) {
      justified.add('network');
    }
  }
  return justified;
}

/// Permissions that are legitimate on their own, because a plugin can need them
/// without any capability implying them.
///
/// `local_plugin_storage` and `clipboard` are host facilities, not provider
/// interfaces, so declaring them is never over-permissioning.
const Set<String> kSelfJustifyingPermissions = <String>{
  'local_plugin_storage',
  'clipboard',
};
