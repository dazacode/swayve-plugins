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

/// One timed word inside a line of lyrics.
///
/// [at] and [until] are both measured from the start of the track, the same
/// origin [SwayveLyricLine.at] uses, so a host highlighting a word never has
/// to know which line it came from or add anything up to place it.
///
/// A word carries an end as well as a start, which a line does not, because
/// the two are read differently. A line is shown until the next one begins,
/// so its end is implied by its neighbour. A word is *lit* while it is being
/// sung and then unlit again, and the gap before the next word — a breath, a
/// held note, a rest — is real: inferring [until] from the following word's
/// [at] would keep the last word of every phrase lit through the silence
/// after it.
@immutable
final class SwayveLyricWord {
  /// Creates a word sung from [at] until [until].
  const SwayveLyricWord({
    required this.at,
    required this.until,
    required this.text,
  });

  /// When this word begins, measured from the start of the track.
  final Duration at;

  /// When this word ends, measured from the start of the track.
  ///
  /// Never before [at]. A provider whose upstream gives it durations rather
  /// than end points adds them itself; the host does no arithmetic here.
  final Duration until;

  /// The word's text, without the whitespace that separated it from its
  /// neighbours. Never empty.
  final String text;

  /// Returns a copy with the given fields replaced.
  SwayveLyricWord copyWith({Duration? at, Duration? until, String? text}) =>
      SwayveLyricWord(
        at: at ?? this.at,
        until: until ?? this.until,
        text: text ?? this.text,
      );

  /// The wire form. [at] and [until] are whole milliseconds.
  Map<String, Object?> toJson() => {
        'atMs': at.inMilliseconds,
        'untilMs': until.inMilliseconds,
        'text': text,
      };

  /// Parses the wire form produced by [toJson].
  static SwayveLyricWord fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveLyricWord', json);
    return SwayveLyricWord(
      at: reader.duration('atMs'),
      until: reader.duration('untilMs'),
      text: reader.string('text'),
    );
  }

  @override
  String toString() =>
      'SwayveLyricWord(${at.inMilliseconds}-${until.inMilliseconds}ms: $text)';

  @override
  bool operator ==(Object other) =>
      other is SwayveLyricWord &&
      at == other.at &&
      until == other.until &&
      text == other.text;

  @override
  int get hashCode => Object.hash(at, until, text);
}

/// The lyrics for one track.
///
/// A provider may return plain text, synced lines, word-level timing, or any
/// combination of the three — they are three independent facts about the same
/// lyric, not three rungs of a ladder, and a provider that has [words] is
/// still expected to fill in [synced] and [plain] for the hosts and surfaces
/// that cannot use them. Returning none of them is not useful: a provider
/// that has no lyrics for a track returns `null` from
/// `SwayveLyricsProvider.lyrics` rather than an empty object, so the host can
/// tell "none found" from "found, but blank".
@immutable
final class SwayveLyrics {
  /// Creates a lyrics document.
  const SwayveLyrics({
    this.plain,
    this.synced,
    this.words,
    this.source,
    this.explicitContent = false,
  });

  /// The whole lyric as plain text, when available.
  final String? plain;

  /// Time-synced lines in ascending [SwayveLyricLine.at] order, when
  /// available.
  final List<SwayveLyricLine>? synced;

  /// Word-level timing, when available: the outer list is lines, the inner
  /// list is the words of that line in the order they are sung.
  ///
  /// Nested rather than one flat list of words because the grouping is what
  /// a host draws with — a karaoke view lays out a line and lights words
  /// across it, and a flat list would make it guess where each line broke.
  ///
  /// Independent of [synced], not derived from it: nothing in this SDK
  /// requires the two to have the same number of lines, or requires either to
  /// be present when the other is. A host that wants a line's start and has
  /// only this reads the first word's [SwayveLyricWord.at], which is why a
  /// word carries an absolute timestamp rather than one relative to its line.
  final List<List<SwayveLyricWord>>? words;

  /// A human-readable attribution for where the lyrics came from.
  ///
  /// The host may be required to display this by the upstream licence, so a
  /// provider should populate it whenever its source demands attribution.
  final String? source;

  /// Whether the text contains explicit language.
  final bool explicitContent;

  /// Whether time-synced lines are available.
  bool get isSynced => synced != null && synced!.isNotEmpty;

  /// Whether word-level timing is available.
  ///
  /// Separate from [isSynced] because the two answer different questions: a
  /// host asking "can I scroll this in time" reads [isSynced], and a host
  /// asking "can I light one word at a time" reads this. A document may
  /// answer yes to one, both or neither.
  bool get hasWordTiming => words != null && words!.isNotEmpty;

  /// Returns a copy with the given fields replaced.
  SwayveLyrics copyWith({
    String? plain,
    List<SwayveLyricLine>? synced,
    List<List<SwayveLyricWord>>? words,
    String? source,
    bool? explicitContent,
  }) =>
      SwayveLyrics(
        plain: plain ?? this.plain,
        synced: synced ?? this.synced,
        words: words ?? this.words,
        source: source ?? this.source,
        explicitContent: explicitContent ?? this.explicitContent,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'plain': plain,
        'synced': synced?.map((line) => line.toJson()).toList(),
        'words': words
            ?.map((line) => line.map((word) => word.toJson()).toList())
            .toList(),
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
      // Absent stays null rather than becoming an empty list, the same way
      // `synced` does: "this provider does not do word timing" and "this
      // lyric has no words" are different claims, and only the first is true
      // of every provider written before the field existed.
      words: reader.has('words')
          ? reader.objectListList('words', SwayveLyricWord.fromJson)
          : null,
      source: reader.stringOrNull('source'),
      explicitContent: reader.boolean('explicitContent'),
    );
  }

  @override
  String toString() => 'SwayveLyrics(synced: ${synced?.length ?? 0}, '
      'words: ${words?.length ?? 0}, source: $source)';

  @override
  bool operator ==(Object other) =>
      other is SwayveLyrics &&
      plain == other.plain &&
      deepEquals(synced, other.synced) &&
      deepEquals(words, other.words) &&
      source == other.source &&
      explicitContent == other.explicitContent;

  @override
  int get hashCode => Object.hash(
        plain,
        deepHash(synced),
        deepHash(words),
        source,
        explicitContent,
      );
}
