import 'package:meta/meta.dart';

import 'enums.dart';
import 'internal/equality.dart';
import 'internal/json.dart';
import 'version.dart';

/// What a plugin is allowed to know about the Swayve instance it is running
/// in.
///
/// Deliberately small. A plugin adapts to the host's *capabilities* —
/// which embeds it can render, which platform it is on, what language the
/// user reads — and learns nothing about the user, the library, or the
/// device beyond that.
///
/// A plugin must branch on the facts here rather than on the platform alone;
/// [supportedEmbeds] in particular can differ between two hosts on the same
/// platform.
@immutable
final class SwayveHostInfo {
  /// Creates host information.
  const SwayveHostInfo({
    required this.swayveVersion,
    required this.swayvePluginApi,
    required this.platform,
    this.supportedEmbeds = const {},
    this.locale = 'en',
    this.region,
  });

  /// The Swayve client's own version.
  ///
  /// Compare against the manifest's `minimumSwayveVersion`; the host has
  /// already refused to load the plugin if it was too old, so this is for
  /// finer-grained behaviour, not for a compatibility gate.
  final Version swayveVersion;

  /// The plugin API level this host implements.
  ///
  /// Always at least the level the plugin declared, because the host refuses
  /// to load a plugin that needs more.
  final int swayvePluginApi;

  /// The platform Swayve is running on.
  final SwayvePlatform platform;

  /// The web embed kinds this host can actually render.
  ///
  /// May be empty. A plugin must check this before returning a
  /// `SwayvePlayableSource.webEmbed`.
  final Set<SwayveWebEmbedKind> supportedEmbeds;

  /// The user's language as a BCP-47 tag, for example `en-GB`.
  ///
  /// Use it to ask upstream services for localized metadata.
  final String locale;

  /// The user's region as an ISO-3166 alpha-2 code, or `null` when unknown.
  ///
  /// Catalogue availability is regional; a plugin that ignores this will show
  /// items the user cannot play.
  final String? region;

  /// Whether this host can render [kind].
  bool supportsEmbed(SwayveWebEmbedKind kind) => supportedEmbeds.contains(kind);

  /// Returns a copy with the given fields replaced.
  SwayveHostInfo copyWith({
    Version? swayveVersion,
    int? swayvePluginApi,
    SwayvePlatform? platform,
    Set<SwayveWebEmbedKind>? supportedEmbeds,
    String? locale,
    String? region,
  }) =>
      SwayveHostInfo(
        swayveVersion: swayveVersion ?? this.swayveVersion,
        swayvePluginApi: swayvePluginApi ?? this.swayvePluginApi,
        platform: platform ?? this.platform,
        supportedEmbeds: supportedEmbeds ?? this.supportedEmbeds,
        locale: locale ?? this.locale,
        region: region ?? this.region,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'swayveVersion': swayveVersion.toJson(),
        'swayvePluginApi': swayvePluginApi,
        'platform': platform.wireName,
        'supportedEmbeds':
            supportedEmbeds.map((embed) => embed.wireName).toList(),
        'locale': locale,
        'region': region,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveHostInfo fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveHostInfo', json);
    return SwayveHostInfo(
      swayveVersion: reader.version('swayveVersion'),
      swayvePluginApi: reader.integer('swayvePluginApi'),
      platform: reader.enumValue('platform', SwayvePlatform.fromWire),
      supportedEmbeds:
          reader.enumSet('supportedEmbeds', SwayveWebEmbedKind.fromWire),
      locale: reader.stringOrNull('locale') ?? 'en',
      region: reader.stringOrNull('region'),
    );
  }

  @override
  String toString() => 'SwayveHostInfo(Swayve $swayveVersion on '
      '${platform.wireName}, api $swayvePluginApi)';

  @override
  bool operator ==(Object other) =>
      other is SwayveHostInfo &&
      swayveVersion == other.swayveVersion &&
      swayvePluginApi == other.swayvePluginApi &&
      platform == other.platform &&
      deepEquals(supportedEmbeds, other.supportedEmbeds) &&
      locale == other.locale &&
      region == other.region;

  @override
  int get hashCode => Object.hash(
        swayveVersion,
        swayvePluginApi,
        platform,
        deepHash(supportedEmbeds),
        locale,
        region,
      );
}
