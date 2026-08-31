/// The manifest schema version this build of the tools implements.
///
/// A manifest declaring a newer `schemaVersion` is rejected — this build
/// cannot know what it means. A manifest declaring an older one stays valid:
/// the format only ever widens (a new capability, a new optional field), so
/// this build reads a `schemaVersion: 1` manifest exactly as a v1 build would.
/// `7` as of the `radio` and `visuals` capabilities (`6` as of
/// `metadata_search`, `5` as of `personal_library_push`, `4` as of
/// `session_capture`, `3` as of `personal_library`, `2` as of
/// `artist_activity` before it); `1` through `6` manifests still validate
/// unchanged.
const int kManifestSchemaVersion = 7;

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
  'artist_activity',
  'personal_library',
  'session_capture',
  'personal_library_push',
  'metadata_search',
  'radio',
  'visuals',
];

/// The closed vocabulary of content a source declares it can be asked for, in
/// schema order.
///
/// Mirrors `SwayveContentType` in the SDK. Kept as a plain list here for the
/// same reason [kCapabilities] is: the tools package validates manifests
/// without depending on the SDK, and the sync between the two lists is what
/// `test/schema_sync_test.dart` exists to hold.
const List<String> kContentTypes = <String>[
  'songs',
  'albums',
  'artists',
  'videos',
];

/// The closed vocabulary of source availabilities, in schema order.
///
/// Mirrors `SwayveSourceAvailability` in the SDK. A manifest states a default
/// rather than an observation — whether a service can answer right now is
/// knowable only to a running plugin — so in practice a manifest either omits
/// this or says `ready`. It is in the vocabulary anyway because a plugin that
/// ships switched off until somebody signs in has an honest use for `off`, and
/// because letting the manifest spell a value the SDK cannot would be exactly
/// the drift the schema sync test forbids.
const List<String> kSourceAvailabilities = <String>[
  'ready',
  'offline',
  'rate_limited',
  'signed_out',
  'off',
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

/// Capability to the permission(s) it is structurally unusable without.
///
/// These are not heuristics. A `webview` capability is the ability to ask the
/// host to render a web view, which is exactly what the `webview` permission
/// grants; an `authentication` capability is a host-mediated auth flow, which
/// is exactly what `external_auth` grants; a `session_capture` capability is
/// both at once — a web view presentation (`webview`) that ends by writing
/// into the credential store (`external_auth`). Declaring a capability
/// without every permission it lists here describes a plugin that cannot do
/// the thing it says it does, so each missing one is an error.
const Map<String, List<String>> kCapabilityRequiredPermission =
    <String, List<String>>{
  'webview': <String>['webview'],
  'authentication': <String>['external_auth'],
  'session_capture': <String>['webview', 'external_auth'],
};

/// Capability to the *other capability* it is structurally unusable without.
///
/// This is the same idea as [kCapabilityRequiredPermission], one level up: a
/// `personal_library` capability describes the signed-in user's own liked
/// tracks, and there is no "own" without a session — which is exactly what
/// `authentication` provides. `personal_library_push` follows the identical
/// shape one level further: it describes *writing* to that same signed-in
/// user's library, and there is no "own library to push to" without first
/// having declared the capability that reads one. Unlike the permission
/// table, the missing thing here is another declared capability, not a
/// grant, so it gets its own map and its own rule rather than being folded
/// into the existing one.
const Map<String, String> kCapabilityRequiredCapability = <String, String>{
  'personal_library': 'authentication',
  'personal_library_push': 'personal_library',
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
  'artist_activity',
  'personal_library',
  'personal_library_push',
  'metadata_search',
  'radio',
  'visuals',
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
    final List<String>? required = kCapabilityRequiredPermission[capability];
    if (required != null) {
      justified.addAll(required);
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

/// The closed vocabulary of `session_capture.capture[].from` values.
///
/// Host-owned and closed on purpose: a plugin names *what* to capture, never
/// *how* — the extraction mechanism behind each entry lives entirely in the
/// host, and a manifest cannot invent a new one. `cookie_header` is the
/// session cookie the platform's native cookie manager holds for the
/// `session_capture.hosts` the flow navigated to; `page_script:youtube_page_id`
/// is a fixed, host-owned JavaScript snippet run via
/// `runJavaScriptReturningResult`, not a plugin-supplied script.
const List<String> kSessionCaptureSources = <String>[
  'cookie_header',
  'page_script:youtube_page_id',
];
