import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';

/// One timed line of lyrics.
///
/// [at] is measured from the start of the track, so the host can drive a
/// karaoke view without knowing anything about the provider's timing format.
@immutable
final class SwayveLyricLine {
  /// Creates a line shown from [at].
  const SwayveLyricLine({required this.at, required this.text});

  /// When this line begins, measured from the start of the track.
  final Duration at;

  /// The line's text. May be empty to represent an instrumental gap.
  final String text;

  /// Returns a copy with the given fields replaced.
  SwayveLyricLine copyWith({Duration? at, String? text}) =>
      SwayveLyricLine(at: at ?? this.at, text: text ?? this.text);

  /// The wire form. [at] is whole milliseconds.
  Map<String, Object?> toJson() => {'atMs': at.inMilliseconds, 'text': text};

  /// Parses the wire form produced by [toJson].
  static SwayveLyricLine fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveLyricLine', json);
    return SwayveLyricLine(
      at: reader.duration('atMs'),
      text: reader.string('text'),
    );
  }

  @override
  String toString() => 'SwayveLyricLine(${at.inMilliseconds}ms: $text)';

  @override
  bool operator ==(Object other) =>
      other is SwayveLyricLine && at == other.at && text == other.text;

  @override
  int get hashCode => Object.hash(at, text);
}

/// The lyrics for one track.
///
/// A provider may return plain text, synced lines, or both. Returning
/// neither is not useful: a provider that has no lyrics for a track returns
/// `null` from `SwayveLyricsProvider.lyrics` rather than an empty object, so
/// the host can tell "none found" from "found, but blank".
@immutable
final class SwayveLyrics {
  /// Creates a lyrics document.
  const SwayveLyrics({
    this.plain,
    this.synced,
    this.source,
    this.explicitContent = false,
  });

  /// The whole lyric as plain text, when available.
  final String? plain;

  /// Time-synced lines in ascending [SwayveLyricLine.at] order, when
  /// available.
  final List<SwayveLyricLine>? synced;

  /// A human-readable attribution for where the lyrics came from.
  ///
  /// The host may be required to display this by the upstream licence, so a
  /// provider should populate it whenever its source demands attribution.
  final String? source;

  /// Whether the text contains explicit language.
  final bool explicitContent;

  /// Whether time-synced lines are available.
  bool get isSynced => synced != null && synced!.isNotEmpty;

  /// Returns a copy with the given fields replaced.
  SwayveLyrics copyWith({
    String? plain,
    List<SwayveLyricLine>? synced,
    String? source,
    bool? explicitContent,
  }) =>
      SwayveLyrics(
        plain: plain ?? this.plain,
        synced: synced ?? this.synced,
        source: source ?? this.source,
        explicitContent: explicitContent ?? this.explicitContent,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'plain': plain,
        'synced': synced?.map((line) => line.toJson()).toList(),
        'source': source,
        'explicitContent': explicitContent,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveLyrics fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveLyrics', json);
    return SwayveLyrics(
      plain: reader.stringOrNull('plain'),
      synced: reader.has('synced')
          ? reader.objectList('synced', SwayveLyricLine.fromJson)
          : null,
      source: reader.stringOrNull('source'),
      explicitContent: reader.boolean('explicitContent'),
    );
  }

  @override
  String toString() =>
      'SwayveLyrics(synced: ${synced?.length ?? 0}, source: $source)';

  @override
  bool operator ==(Object other) =>
      other is SwayveLyrics &&
      plain == other.plain &&
      deepEquals(synced, other.synced) &&
      source == other.source &&
      explicitContent == other.explicitContent;

  @override
  int get hashCode =>
      Object.hash(plain, deepHash(synced), source, explicitContent);
}
