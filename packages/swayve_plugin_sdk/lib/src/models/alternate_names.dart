import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';

/// The other names a piece of music goes by, as the provider itself publishes
/// them.
///
/// A great many services already hold this. A Japanese release carries its own
/// title and a romanization side by side; a Korean one carries the Hangul and
/// the English the label registered; a service that serves several markets
/// carries a translated title per market. All of it is sitting in payloads the
/// plugins here already fetch and currently throw away, and the host is left
/// guessing at it afterwards with a transliteration table and a translation
/// service.
///
/// That is the whole reason this type exists. A name the service published is
/// the best answer anyone in this system will ever have — better than a
/// mechanical transliteration, which is only correct within the script it
/// covers, and far better than a machine translation, which is a guess. A
/// plugin that fills this in ends the guessing for that track permanently, and
/// a plugin that leaves it empty costs nothing.
///
/// ## Why the original is here at all
///
/// [originalTitle] looks redundant next to `SwayveTrack.title`, and for most
/// providers it is — a provider whose catalogue is in one script puts the title
/// in `title` and stops. It is here for the providers where it is not: some
/// services answer a search in the querying market's script and keep the
/// release's own name in a second field, so `title` arrives already romanized
/// and the real name is the one that would be lost. A plugin in that position
/// has no way to say so without this, and the host must never be in the
/// position of having only a romanization and believing it canonical.
///
/// Every field is optional and [aliases] is never null, only empty. A provider
/// that publishes nothing here produces [SwayveAlternateNames.none], never a
/// fabricated one: a plugin must not compute a romanization to fill this in.
/// The host has a transliterator for that and it stamps its output with a
/// different origin precisely so the two can be told apart later.
@immutable
final class SwayveAlternateNames {
  /// Creates a set of alternate names.
  const SwayveAlternateNames({
    this.originalTitle,
    this.romanizedTitle,
    this.translatedTitle,
    this.originalArtist,
    this.romanizedArtist,
    this.translatedArtist,
    this.originalAlbum,
    this.romanizedAlbum,
    this.translatedAlbum,
    this.aliases = const [],
  });

  /// Nothing published. A `const` singleton rather than a nullable field on
  /// `SwayveTrack`, so every caller can read `.aliases` without a null check
  /// and the overwhelmingly common case is one object rather than one per
  /// track.
  static const SwayveAlternateNames none = SwayveAlternateNames();

  /// The title in the script the release itself uses, when the provider keeps
  /// it apart from the title it answered with.
  final String? originalTitle;

  /// The title transliterated into Latin script, as the provider publishes it.
  final String? romanizedTitle;

  /// The title rendered in another language, as the provider publishes it.
  final String? translatedTitle;

  /// The credited artist in the script they use, when the provider keeps it
  /// apart from the name it answered with.
  final String? originalArtist;

  /// The credited artist transliterated into Latin script.
  final String? romanizedArtist;

  /// The credited artist's name in another language.
  final String? translatedArtist;

  /// The release title in the script it uses, when the provider keeps it apart
  /// from the one it answered with.
  final String? originalAlbum;

  /// The release title transliterated into Latin script.
  final String? romanizedAlbum;

  /// The release title in another language.
  final String? translatedAlbum;

  /// Any other name this music goes by that does not fit the nine fields
  /// above — a service's alternate spellings, a release's other titles, an
  /// artist's other names, a track's subtitle.
  ///
  /// Free-form and unordered on purpose. The nine fields are the shapes worth
  /// naming because a host can label them; this is the bucket for everything
  /// else, and a host that only wants "every string this song answers to" —
  /// which is what a search index wants — reads it exactly as it reads them.
  final List<String> aliases;

  /// Whether the provider published nothing at all.
  bool get isEmpty =>
      originalTitle == null &&
      romanizedTitle == null &&
      translatedTitle == null &&
      originalArtist == null &&
      romanizedArtist == null &&
      translatedArtist == null &&
      originalAlbum == null &&
      romanizedAlbum == null &&
      translatedAlbum == null &&
      aliases.isEmpty;

  /// Whether the provider published anything.
  bool get isNotEmpty => !isEmpty;

  /// Every distinct name in here, for a caller that only wants the strings.
  ///
  /// Nulls and blanks are dropped; nothing is de-duplicated, because a host
  /// that indexes these normalizes before it compares and two names differing
  /// only in punctuation are one entry to it and two to this.
  List<String> get allNames => [
        for (final name in [
          originalTitle,
          romanizedTitle,
          translatedTitle,
          originalArtist,
          romanizedArtist,
          translatedArtist,
          originalAlbum,
          romanizedAlbum,
          translatedAlbum,
          ...aliases,
        ])
          if (name != null && name.trim().isNotEmpty) name,
      ];

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` for a field keeps the current value; construct a new set
  /// to clear one.
  SwayveAlternateNames copyWith({
    String? originalTitle,
    String? romanizedTitle,
    String? translatedTitle,
    String? originalArtist,
    String? romanizedArtist,
    String? translatedArtist,
    String? originalAlbum,
    String? romanizedAlbum,
    String? translatedAlbum,
    List<String>? aliases,
  }) =>
      SwayveAlternateNames(
        originalTitle: originalTitle ?? this.originalTitle,
        romanizedTitle: romanizedTitle ?? this.romanizedTitle,
        translatedTitle: translatedTitle ?? this.translatedTitle,
        originalArtist: originalArtist ?? this.originalArtist,
        romanizedArtist: romanizedArtist ?? this.romanizedArtist,
        translatedArtist: translatedArtist ?? this.translatedArtist,
        originalAlbum: originalAlbum ?? this.originalAlbum,
        romanizedAlbum: romanizedAlbum ?? this.romanizedAlbum,
        translatedAlbum: translatedAlbum ?? this.translatedAlbum,
        aliases: aliases ?? this.aliases,
      );

  /// The wire form. Null fields are omitted, and an empty [aliases] with them,
  /// so a track that publishes one romanized title does not carry eight nulls
  /// and an empty list through every response.
  Map<String, Object?> toJson() => pruneNulls({
        'originalTitle': originalTitle,
        'romanizedTitle': romanizedTitle,
        'translatedTitle': translatedTitle,
        'originalArtist': originalArtist,
        'romanizedArtist': romanizedArtist,
        'translatedArtist': translatedArtist,
        'originalAlbum': originalAlbum,
        'romanizedAlbum': romanizedAlbum,
        'translatedAlbum': translatedAlbum,
        'aliases': aliases.isEmpty ? null : aliases,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveAlternateNames fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveAlternateNames', json);
    return SwayveAlternateNames(
      originalTitle: reader.stringOrNull('originalTitle'),
      romanizedTitle: reader.stringOrNull('romanizedTitle'),
      translatedTitle: reader.stringOrNull('translatedTitle'),
      originalArtist: reader.stringOrNull('originalArtist'),
      romanizedArtist: reader.stringOrNull('romanizedArtist'),
      translatedArtist: reader.stringOrNull('translatedArtist'),
      originalAlbum: reader.stringOrNull('originalAlbum'),
      romanizedAlbum: reader.stringOrNull('romanizedAlbum'),
      translatedAlbum: reader.stringOrNull('translatedAlbum'),
      aliases: reader.stringList('aliases'),
    );
  }

  @override
  String toString() => 'SwayveAlternateNames(${allNames.join(', ')})';

  @override
  bool operator ==(Object other) =>
      other is SwayveAlternateNames &&
      originalTitle == other.originalTitle &&
      romanizedTitle == other.romanizedTitle &&
      translatedTitle == other.translatedTitle &&
      originalArtist == other.originalArtist &&
      romanizedArtist == other.romanizedArtist &&
      translatedArtist == other.translatedArtist &&
      originalAlbum == other.originalAlbum &&
      romanizedAlbum == other.romanizedAlbum &&
      translatedAlbum == other.translatedAlbum &&
      deepEquals(aliases, other.aliases);

  @override
  int get hashCode => Object.hash(
        originalTitle,
        romanizedTitle,
        translatedTitle,
        originalArtist,
        romanizedArtist,
        translatedArtist,
        originalAlbum,
        romanizedAlbum,
        translatedAlbum,
        deepHash(aliases),
      );
}
