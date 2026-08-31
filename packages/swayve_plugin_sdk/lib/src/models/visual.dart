import 'package:meta/meta.dart';

import '../internal/json.dart';

/// What kind of moving image a [SwayveVisual] points at.
///
/// The host renders the two differently and cannot infer which it has from
/// the media alone, so the provider says. A music video is content in its own
/// right: it has a beginning, it is worth seeing full-screen, and running out
/// of it mid-track is normal. A motion cover is scenery: it is short, it is
/// meant to be looked past rather than at, and it is expected to run for as
/// long as the song does.
enum SwayveVisualKind {
  /// A music video — a filmed piece the length of the recording, or close to
  /// it, that a person might choose to watch.
  video,

  /// A short looping animation standing in for the sleeve — a moving cover,
  /// a canvas, a few seconds of motion behind the now-playing surface.
  ///
  /// Its wire name is `motion_artwork`.
  motionArtwork;

  /// The wire spelling of this kind.
  String get wireName => switch (this) {
        SwayveVisualKind.video => 'video',
        SwayveVisualKind.motionArtwork => 'motion_artwork',
      };

  /// The kind named [wire], or `null` if unknown.
  static SwayveVisualKind? fromWire(String wire) {
    for (final value in SwayveVisualKind.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// Moving visuals the host may play behind a track.
///
/// Principle 5 holds here exactly as it does for [SwayveImageRef]: a plugin
/// hands over a location and the facts needed to lay it out, never decoded
/// frames and never a widget. The host owns the surface, decides whether the
/// current one is even large enough to be worth filling, and is free to
/// ignore the whole thing.
///
/// A visual is an accompaniment, never the audio. The host keeps playing the
/// track it resolved through `SwayveStreamProvider` and renders this behind
/// it muted, so a provider must not return something whose only value is its
/// soundtrack, and must not expect its own audio to be heard.
@immutable
final class SwayveVisual {
  /// Creates a visual.
  const SwayveVisual({
    required this.uri,
    required this.kind,
    this.aspectRatio,
    this.loops = true,
    this.source,
    this.duration,
  });

  /// Where the media lives.
  ///
  /// Usually `https:`, and usually something a video element can play
  /// directly — a progressive file or an HLS manifest. Not a page to embed:
  /// there is no web-embed form of a visual, because a host that cannot play
  /// the media itself is better off drawing the artwork it already has.
  final Uri uri;

  /// Whether this is a video or a motion cover. See [SwayveVisualKind].
  final SwayveVisualKind kind;

  /// Width divided by height, when the provider knows it.
  ///
  /// Reported rather than left to be discovered because the host lays the
  /// surface out before a single byte arrives, and a surface that resizes
  /// once the first frame decodes is a visible jolt on the now-playing
  /// screen. Null means "size it once you know", not "assume 16:9".
  final double? aspectRatio;

  /// Whether the host should play it again from the start when it ends.
  ///
  /// Defaults to `true`, which is right for the overwhelmingly common case: a
  /// motion cover is scenery and is meant to run for the length of the song,
  /// and a video shorter than the recording still looks better repeating than
  /// stopping on a frozen frame. A provider sets it to `false` when running
  /// the media twice would be wrong — a video with an ending that means
  /// something, or one that is longer than the track anyway.
  final bool loops;

  /// A human-readable attribution for where the visual came from.
  ///
  /// The same role [SwayveLyrics.source] plays: the host may be required to
  /// display it by the upstream licence, so a provider should populate it
  /// whenever its source demands attribution.
  final String? source;

  /// How long the media runs, when the provider knows.
  ///
  /// Purely informational — the host is playing the track, not this, and
  /// never syncs one to the other. Worth reporting because a host may choose
  /// between two visuals, or decline a three-second loop, on this alone.
  final Duration? duration;

  /// Returns a copy with the given fields replaced.
  SwayveVisual copyWith({
    Uri? uri,
    SwayveVisualKind? kind,
    double? aspectRatio,
    bool? loops,
    String? source,
    Duration? duration,
  }) =>
      SwayveVisual(
        uri: uri ?? this.uri,
        kind: kind ?? this.kind,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        loops: loops ?? this.loops,
        source: source ?? this.source,
        duration: duration ?? this.duration,
      );

  /// The wire form. Null fields are omitted; [duration] is milliseconds.
  Map<String, Object?> toJson() => pruneNulls({
        'uri': uri.toString(),
        'kind': kind.wireName,
        'aspectRatio': aspectRatio,
        'loops': loops,
        'source': source,
        'durationMs': durationToJson(duration),
      });

  /// Parses the wire form produced by [toJson].
  static SwayveVisual fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveVisual', json);
    return SwayveVisual(
      uri: reader.uri('uri'),
      kind: reader.enumValue('kind', SwayveVisualKind.fromWire),
      aspectRatio: reader.numberOrNull('aspectRatio'),
      // An absent `loops` reads as `true`, matching the constructor's own
      // default: the field says "stop at the end", and a provider that never
      // mentioned it did not mean to say that.
      loops: reader.boolean('loops', orElse: true),
      source: reader.stringOrNull('source'),
      duration: reader.durationOrNull('durationMs'),
    );
  }

  @override
  String toString() => 'SwayveVisual(${kind.wireName}, $uri)';

  @override
  bool operator ==(Object other) =>
      other is SwayveVisual &&
      uri == other.uri &&
      kind == other.kind &&
      aspectRatio == other.aspectRatio &&
      loops == other.loops &&
      source == other.source &&
      duration == other.duration;

  @override
  int get hashCode =>
      Object.hash(uri, kind, aspectRatio, loops, source, duration);
}
