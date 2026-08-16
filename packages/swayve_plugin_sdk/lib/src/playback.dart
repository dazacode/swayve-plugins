import 'package:meta/meta.dart';

import 'enums.dart';
import 'internal/equality.dart';
import 'internal/json.dart';
import 'models/availability.dart';

/// A web surface the host can render to play something it cannot decode
/// itself.
///
/// Principle 2 in its sharpest form: the host knows "render this embed", not
/// "this is YouTube". A plugin must check `SwayveHostInfo.supportedEmbeds`
/// before returning one — an embed kind the host cannot render is an
/// unplayable track, and the plugin should say so rather than hand over
/// something that will fail at playback time.
@immutable
final class SwayveWebEmbed {
  /// Creates a web embed.
  const SwayveWebEmbed({
    required this.kind,
    required this.uri,
    this.controls = const {},
    this.userAgent,
    this.document,
  });

  /// Which kind of web surface this needs.
  final SwayveWebEmbedKind kind;

  /// The page to load.
  final Uri uri;

  /// The transport controls the host may drive.
  ///
  /// A control that is absent is unavailable: the host must disable the
  /// corresponding affordance rather than trying it. An embed with no
  /// controls is playable but not controllable, which the host may reject.
  final Set<SwayveEmbedControl> controls;

  /// A user agent the host must present when loading [uri], when the
  /// upstream service requires a specific one.
  final String? userAgent;

  /// A page to load *instead of navigating to* [uri], with [uri] as its base.
  ///
  /// This is what makes [controls] mean anything. Without it a host can render
  /// a service's player and nothing else: it has the page on screen, it knows
  /// from [controls] that the page could in principle be paused, and it has no
  /// way whatsoever to pause it — because the incantation is the service's own
  /// JavaScript, and a host that knew it would be a host with hardcoded
  /// knowledge of one plugin, which principle 2 forbids.
  ///
  /// A document moves that knowledge to the only place it belongs. The plugin
  /// writes a small page that loads its service's player and exposes it through
  /// the vocabulary in [SwayveEmbedBridge]; the host loads the page, speaks that
  /// vocabulary, and never learns whose player is behind it. Every service with
  /// an embeddable player and a scripting API can be adapted this way, and the
  /// adapter is a dozen lines.
  ///
  /// Null is the ordinary case and keeps the old behaviour exactly: the host
  /// navigates to [uri] and the page brings its own controls. A plugin that
  /// cannot script its player should leave this null rather than ship a
  /// document that half-works — [controls] should then be empty, and the host
  /// will draw the page's own chrome instead of its own transport.
  ///
  /// The host loads this with [uri] as the base address, so relative URLs and
  /// the page's origin resolve as though it had been served from there. That
  /// matters: a player API script will refuse to run from `about:blank`.
  final String? document;

  /// Whether this embed can be driven by the host rather than only displayed.
  ///
  /// Both halves are required and neither implies the other: a [document] with
  /// no [controls] declares nothing drivable, and controls without a document
  /// is a promise with no way to keep it.
  bool get isDrivable => document != null && controls.isNotEmpty;

  /// Returns a copy with the given fields replaced.
  SwayveWebEmbed copyWith({
    SwayveWebEmbedKind? kind,
    Uri? uri,
    Set<SwayveEmbedControl>? controls,
    String? userAgent,
    String? document,
  }) =>
      SwayveWebEmbed(
        kind: kind ?? this.kind,
        uri: uri ?? this.uri,
        controls: controls ?? this.controls,
        userAgent: userAgent ?? this.userAgent,
        document: document ?? this.document,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'kind': kind.wireName,
        'uri': uri.toString(),
        'controls': controls.map((control) => control.wireName).toList(),
        'userAgent': userAgent,
        'document': document,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveWebEmbed fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveWebEmbed', json);
    return SwayveWebEmbed(
      kind: reader.enumValue('kind', SwayveWebEmbedKind.fromWire),
      uri: reader.uri('uri'),
      controls: reader.enumSet('controls', SwayveEmbedControl.fromWire),
      userAgent: reader.stringOrNull('userAgent'),
      document: reader.stringOrNull('document'),
    );
  }

  @override
  String toString() => 'SwayveWebEmbed(${kind.wireName}, $uri)';

  @override
  bool operator ==(Object other) =>
      other is SwayveWebEmbed &&
      kind == other.kind &&
      uri == other.uri &&
      deepEquals(controls, other.controls) &&
      userAgent == other.userAgent &&
      document == other.document;

  @override
  int get hashCode =>
      Object.hash(kind, uri, deepHash(controls), userAgent, document);
}

/// What the host would prefer, when the provider has a choice.
///
/// Every field is a hint. A provider that cannot honour one returns its best
/// available source anyway; it never fails a resolution because a hint could
/// not be met. The one exception is [allowWebEmbed]: when it is `false` the
/// host cannot render an embed at all, so returning one is a bug.
@immutable
final class SwayvePlaybackHints {
  /// Creates a set of hints.
  const SwayvePlaybackHints({
    this.preferAudioOnly = true,
    this.maxBitrateKbps,
    this.allowWebEmbed = true,
  });

  /// The host's defaults: audio-only, unbounded bitrate, embeds allowed.
  static const SwayvePlaybackHints defaults = SwayvePlaybackHints();

  /// Whether to prefer an audio-only rendition over a video one.
  ///
  /// Defaults to `true`: Swayve is a music player, and an audio-only stream
  /// saves the user bandwidth.
  final bool preferAudioOnly;

  /// A soft ceiling on bitrate, in kbps, or `null` for no preference.
  ///
  /// Set by the host from the user's data-saving settings.
  final int? maxBitrateKbps;

  /// Whether the host is able and willing to render a web embed right now.
  ///
  /// `false` when the platform has no embed support, or when the user has
  /// opted out. A provider that only has an embed for this track must then
  /// throw `SwayvePluginUnsupportedException`.
  final bool allowWebEmbed;

  /// Returns a copy with the given fields replaced.
  SwayvePlaybackHints copyWith({
    bool? preferAudioOnly,
    int? maxBitrateKbps,
    bool? allowWebEmbed,
  }) =>
      SwayvePlaybackHints(
        preferAudioOnly: preferAudioOnly ?? this.preferAudioOnly,
        maxBitrateKbps: maxBitrateKbps ?? this.maxBitrateKbps,
        allowWebEmbed: allowWebEmbed ?? this.allowWebEmbed,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'preferAudioOnly': preferAudioOnly,
        'maxBitrateKbps': maxBitrateKbps,
        'allowWebEmbed': allowWebEmbed,
      });

  /// Parses the wire form produced by [toJson].
  static SwayvePlaybackHints fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayvePlaybackHints', json);
    return SwayvePlaybackHints(
      preferAudioOnly: reader.boolean('preferAudioOnly', orElse: true),
      maxBitrateKbps: reader.integerOrNull('maxBitrateKbps'),
      allowWebEmbed: reader.boolean('allowWebEmbed', orElse: true),
    );
  }

  @override
  String toString() => 'SwayvePlaybackHints(preferAudioOnly: '
      '$preferAudioOnly, maxBitrateKbps: $maxBitrateKbps, '
      'allowWebEmbed: $allowWebEmbed)';

  @override
  bool operator ==(Object other) =>
      other is SwayvePlaybackHints &&
      preferAudioOnly == other.preferAudioOnly &&
      maxBitrateKbps == other.maxBitrateKbps &&
      allowWebEmbed == other.allowWebEmbed;

  @override
  int get hashCode =>
      Object.hash(preferAudioOnly, maxBitrateKbps, allowWebEmbed);
}

/// Everything the host needs to start playing one item, and nothing about
/// where it came from.
///
/// A stream provider resolves a media id to one of these. The host switches
/// on [kind] and hands the result to its player; it never learns which
/// service produced it.
///
/// What an implementer must guarantee:
/// * [uri] is non-null for every kind except `webEmbed`, and [embed] is
///   non-null only for `webEmbed` — the named constructors enforce this;
/// * [headers] are sufficient on their own: the host replays exactly these
///   and adds nothing;
/// * [expiresIn], when set, is honest — the host re-resolves after it rather
///   than retrying a dead URL;
/// * [availability] agrees with what the manifest's `media` block promised.
@immutable
final class SwayvePlayableSource {
  const SwayvePlayableSource._({
    required this.kind,
    this.uri,
    this.embed,
    this.headers = const {},
    this.expiresIn,
    this.availability = SwayveAvailability.streamOnly,
    this.mimeType,
  });

  /// A single progressive media URL the host's player can fetch directly.
  const SwayvePlayableSource.directUrl(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? expiresIn,
    SwayveAvailability availability = SwayveAvailability.streamOnly,
    String? mimeType,
  }) : this._(
          kind: SwayvePlayableKind.directUrl,
          uri: uri,
          headers: headers,
          expiresIn: expiresIn,
          availability: availability,
          mimeType: mimeType,
        );

  /// An HLS manifest URL.
  const SwayvePlayableSource.hls(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? expiresIn,
    SwayveAvailability availability = SwayveAvailability.streamOnly,
    String? mimeType,
  }) : this._(
          kind: SwayvePlayableKind.hlsUrl,
          uri: uri,
          headers: headers,
          expiresIn: expiresIn,
          availability: availability,
          mimeType: mimeType,
        );

  /// A DASH manifest URL.
  const SwayvePlayableSource.dash(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? expiresIn,
    SwayveAvailability availability = SwayveAvailability.streamOnly,
    String? mimeType,
  }) : this._(
          kind: SwayvePlayableKind.dashUrl,
          uri: uri,
          headers: headers,
          expiresIn: expiresIn,
          availability: availability,
          mimeType: mimeType,
        );

  /// A file the plugin has already placed on this device.
  ///
  /// The plugin has no filesystem access of its own; this is for a path the
  /// host itself downloaded on the plugin's behalf. [availability] should
  /// report `onDevice: true`.
  const SwayvePlayableSource.localFile(
    Uri uri, {
    SwayveAvailability availability = const SwayveAvailability(onDevice: true),
    String? mimeType,
  }) : this._(
          kind: SwayvePlayableKind.localFile,
          uri: uri,
          availability: availability,
          mimeType: mimeType,
        );

  /// Playback inside a host-rendered web surface.
  ///
  /// Only legal when the host listed the embed's kind in
  /// `SwayveHostInfo.supportedEmbeds` and the request's hints allowed it.
  const SwayvePlayableSource.webEmbed(
    SwayveWebEmbed embed, {
    Duration? expiresIn,
    SwayveAvailability availability = SwayveAvailability.streamOnly,
  }) : this._(
          kind: SwayvePlayableKind.webEmbed,
          embed: embed,
          expiresIn: expiresIn,
          availability: availability,
        );

  /// How the host should play this.
  final SwayvePlayableKind kind;

  /// Where the media lives, for every kind except `webEmbed`.
  final Uri? uri;

  /// The embed to render, for `webEmbed` only.
  final SwayveWebEmbed? embed;

  /// Request headers the host must send with every request for [uri].
  ///
  /// The host sends these and nothing else of the plugin's; it does not
  /// merge in cookies or credentials of its own.
  final Map<String, String> headers;

  /// How long this source stays valid.
  ///
  /// After it elapses the host must call the stream provider again rather
  /// than reusing the URL. `null` means the plugin makes no claim, and the
  /// host may cache it for the session.
  final Duration? expiresIn;

  /// What may be done with this item, restated at resolution time.
  ///
  /// Must agree with the manifest's `media` block: a plugin whose manifest
  /// says `downloadable: false` may not hand back a downloadable source.
  final SwayveAvailability availability;

  /// The media MIME type, when the plugin knows it.
  ///
  /// Helps the host pick a decoder without sniffing the stream.
  final String? mimeType;

  /// Whether this source is a web embed rather than a media URL.
  bool get isWebEmbed => kind == SwayvePlayableKind.webEmbed;

  /// Returns a copy with the given fields replaced. [kind] is preserved.
  SwayvePlayableSource copyWith({
    Uri? uri,
    SwayveWebEmbed? embed,
    Map<String, String>? headers,
    Duration? expiresIn,
    SwayveAvailability? availability,
    String? mimeType,
  }) =>
      SwayvePlayableSource._(
        kind: kind,
        uri: uri ?? this.uri,
        embed: embed ?? this.embed,
        headers: headers ?? this.headers,
        expiresIn: expiresIn ?? this.expiresIn,
        availability: availability ?? this.availability,
        mimeType: mimeType ?? this.mimeType,
      );

  /// The wire form. Null and empty fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'kind': kind.wireName,
        'uri': uri?.toString(),
        'embed': embed?.toJson(),
        'headers': headers.isEmpty ? null : headers,
        'expiresInMs': durationToJson(expiresIn),
        'availability': availability.toJson(),
        'mimeType': mimeType,
      });

  /// Parses the wire form produced by [toJson].
  ///
  /// Throws `SwayvePluginMalformedResponseException` when the payload's kind
  /// and payload disagree — a `webEmbed` without an embed, or a URL kind
  /// without a URI.
  static SwayvePlayableSource fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayvePlayableSource', json);
    final kind = reader.enumValue('kind', SwayvePlayableKind.fromWire);
    final availability = reader.has('availability')
        ? reader.object('availability', SwayveAvailability.fromJson)
        : SwayveAvailability.streamOnly;
    final expiresIn = reader.durationOrNull('expiresInMs');
    if (kind == SwayvePlayableKind.webEmbed) {
      final embed = reader.objectOrNull('embed', SwayveWebEmbed.fromJson);
      if (embed == null) {
        malformed('SwayvePlayableSource.embed: required for a web_embed.');
      }
      return SwayvePlayableSource.webEmbed(
        embed,
        expiresIn: expiresIn,
        availability: availability,
      );
    }
    final uri = reader.uriOrNull('uri');
    if (uri == null) {
      malformed(
        'SwayvePlayableSource.uri: required for ${kind.wireName}.',
      );
    }
    final headers = reader.stringMap('headers');
    final mimeType = reader.stringOrNull('mimeType');
    return switch (kind) {
      SwayvePlayableKind.directUrl => SwayvePlayableSource.directUrl(
          uri,
          headers: headers,
          expiresIn: expiresIn,
          availability: availability,
          mimeType: mimeType,
        ),
      SwayvePlayableKind.hlsUrl => SwayvePlayableSource.hls(
          uri,
          headers: headers,
          expiresIn: expiresIn,
          availability: availability,
          mimeType: mimeType,
        ),
      SwayvePlayableKind.dashUrl => SwayvePlayableSource.dash(
          uri,
          headers: headers,
          expiresIn: expiresIn,
          availability: availability,
          mimeType: mimeType,
        ),
      SwayvePlayableKind.localFile => SwayvePlayableSource.localFile(
          uri,
          availability: availability,
          mimeType: mimeType,
        ),
      SwayvePlayableKind.webEmbed =>
        malformed('SwayvePlayableSource: unreachable web_embed branch.'),
    };
  }

  @override
  String toString() =>
      'SwayvePlayableSource(${kind.wireName}, ${uri ?? embed?.uri})';

  @override
  bool operator ==(Object other) =>
      other is SwayvePlayableSource &&
      kind == other.kind &&
      uri == other.uri &&
      embed == other.embed &&
      deepEquals(headers, other.headers) &&
      expiresIn == other.expiresIn &&
      availability == other.availability &&
      mimeType == other.mimeType;

  @override
  int get hashCode => Object.hash(
        kind,
        uri,
        embed,
        deepHash(headers),
        expiresIn,
        availability,
        mimeType,
      );
}
