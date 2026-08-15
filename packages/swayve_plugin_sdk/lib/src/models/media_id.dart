import 'package:meta/meta.dart';

import '../constants.dart';
import '../internal/json.dart';

/// A globally unique identifier for a piece of media supplied by a plugin.
///
/// Principle 2: the client has zero hardcoded knowledge of any specific
/// plugin. [value] is therefore opaque to the host — it is whatever the
/// provider's own catalogue calls this item, and the host must never parse,
/// pattern-match or reason about it. The only structure the host relies on is
/// [pluginId], which tells it who to route a request back to.
///
/// [uri] is the canonical serialization: `swayve://<pluginId>/<value>` with
/// [value] percent-encoded. The round trip through [parse] is exact for every
/// possible [value], including ones containing `/`, spaces, `?`, `#` and
/// non-ASCII characters.
@immutable
final class SwayveMediaId {
  /// Creates an identifier owned by [pluginId] wrapping the provider-native
  /// [value].
  const SwayveMediaId(this.pluginId, this.value);

  /// The id of the plugin that minted this identifier.
  ///
  /// Matches the `id` field of that plugin's `plugin.json`, so the host can
  /// route any request about this item back to its owner.
  final String pluginId;

  /// The provider's own identifier for the item.
  ///
  /// Opaque to the host. It may contain any character, including ones that
  /// are not URI-safe.
  final String value;

  /// The canonical URI form: `swayve://<pluginId>/<percent-encoded value>`.
  ///
  /// Stable across versions and safe to persist. Feed it back to [parse] to
  /// recover exactly this identifier.
  String get uri =>
      '$kSwayveMediaIdScheme://$pluginId/${Uri.encodeComponent(value)}';

  /// Parses the [uri] form back into an identifier.
  ///
  /// Throws `SwayvePluginMalformedResponseException` when [uri] does not use
  /// the `swayve` scheme, omits a plugin id, or contains an invalid
  /// percent-escape. Use [tryParse] when a failure is expected and not
  /// exceptional.
  static SwayveMediaId parse(String uri) {
    final parsed = tryParse(uri);
    if (parsed == null) {
      malformed("SwayveMediaId: '$uri' is not a swayve:// media id.");
    }
    return parsed;
  }

  /// Parses the [uri] form, returning `null` when it is not a valid media id.
  static SwayveMediaId? tryParse(String uri) {
    const prefix = '$kSwayveMediaIdScheme://';
    if (!uri.startsWith(prefix)) return null;
    final rest = uri.substring(prefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    final pluginId = rest.substring(0, slash);
    final encoded = rest.substring(slash + 1);
    try {
      return SwayveMediaId(pluginId, Uri.decodeComponent(encoded));
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Returns a copy with the given parts replaced.
  SwayveMediaId copyWith({String? pluginId, String? value}) =>
      SwayveMediaId(pluginId ?? this.pluginId, value ?? this.value);

  /// The wire form: `{"pluginId": ..., "value": ...}`.
  Map<String, Object?> toJson() => {'pluginId': pluginId, 'value': value};

  /// Parses the wire form produced by [toJson].
  ///
  /// Also accepts `{"uri": "swayve://..."}` so that a payload which stored
  /// the compact form still round-trips.
  static SwayveMediaId fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveMediaId', json);
    if (!reader.has('pluginId') && reader.has('uri')) {
      return parse(reader.string('uri'));
    }
    return SwayveMediaId(reader.string('pluginId'), reader.string('value'));
  }

  @override
  String toString() => uri;

  @override
  bool operator ==(Object other) =>
      other is SwayveMediaId &&
      pluginId == other.pluginId &&
      value == other.value;

  @override
  int get hashCode => Object.hash(pluginId, value);
}
