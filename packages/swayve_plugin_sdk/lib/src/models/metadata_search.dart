import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';

/// What the host already knows about a track it is asking
/// `SwayveMetadataSearchProvider.searchTrack` to identify.
///
/// Unlike [SwayveSearchQuery], this is not a person typing a phrase — it is
/// every field the host's own record for the track already carries, however
/// incomplete or possibly wrong. A provider should use whatever it can and
/// ignore the rest; [title] and at least one of [artists] is the practical
/// floor below which no provider can be expected to answer anything.
@immutable
final class SwayveMetadataQuery {
  /// Creates a query.
  const SwayveMetadataQuery({
    this.title,
    this.artists = const [],
    this.album,
    this.year,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.isrc,
    this.sourceUrl,
    this.providerId,
  });

  /// The title the host's record has, when it has one.
  final String? title;

  /// Credited artists, in whatever order the host's record has them.
  final List<String> artists;

  /// The album the host's record has, when it has one.
  final String? album;

  /// The release year the host's record has, when it has one.
  final int? year;

  /// How long the host's own copy runs, when it has one. The single most
  /// useful signal for telling two versions of the same song apart — see
  /// `SwayveMetadataCandidate.duration`.
  final Duration? duration;

  /// The track's position within its disc, when the host's record has one.
  final int? trackNumber;

  /// The disc number within a multi-disc release, when the host's record
  /// has one.
  final int? discNumber;

  /// The International Standard Recording Code, when the host already has
  /// one on file. An exact match on this is stronger evidence than every
  /// other field combined.
  final String? isrc;

  /// A URL the host already associates with this track, if any — not
  /// necessarily one this provider issued.
  final Uri? sourceUrl;

  /// An id this *same* provider previously gave the host for this track, for
  /// a repeat lookup. Never another provider's id.
  final String? providerId;

  /// Returns a copy with the given fields replaced.
  SwayveMetadataQuery copyWith({
    String? title,
    List<String>? artists,
    String? album,
    int? year,
    Duration? duration,
    int? trackNumber,
    int? discNumber,
    String? isrc,
    Uri? sourceUrl,
    String? providerId,
  }) =>
      SwayveMetadataQuery(
        title: title ?? this.title,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        year: year ?? this.year,
        duration: duration ?? this.duration,
        trackNumber: trackNumber ?? this.trackNumber,
        discNumber: discNumber ?? this.discNumber,
        isrc: isrc ?? this.isrc,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        providerId: providerId ?? this.providerId,
      );

  /// The wire form. Null fields are omitted; [duration] is milliseconds.
  Map<String, Object?> toJson() => pruneNulls({
        'title': title,
        'artists': artists.isEmpty ? null : artists,
        'album': album,
        'year': year,
        'durationMs': durationToJson(duration),
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'isrc': isrc,
        'sourceUrl': sourceUrl?.toString(),
        'providerId': providerId,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveMetadataQuery fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveMetadataQuery', json);
    return SwayveMetadataQuery(
      title: reader.stringOrNull('title'),
      artists: reader.stringList('artists'),
      album: reader.stringOrNull('album'),
      year: reader.integerOrNull('year'),
      duration: reader.durationOrNull('durationMs'),
      trackNumber: reader.integerOrNull('trackNumber'),
      discNumber: reader.integerOrNull('discNumber'),
      isrc: reader.stringOrNull('isrc'),
      sourceUrl: reader.uriOrNull('sourceUrl'),
      providerId: reader.stringOrNull('providerId'),
    );
  }

  @override
  String toString() => 'SwayveMetadataQuery($title, $artists)';

  @override
  bool operator ==(Object other) =>
      other is SwayveMetadataQuery &&
      title == other.title &&
      deepEquals(artists, other.artists) &&
      album == other.album &&
      year == other.year &&
      duration == other.duration &&
      trackNumber == other.trackNumber &&
      discNumber == other.discNumber &&
      isrc == other.isrc &&
      sourceUrl == other.sourceUrl &&
      providerId == other.providerId;

  @override
  int get hashCode => Object.hash(
        title,
        deepHash(artists),
        album,
        year,
        duration,
        trackNumber,
        discNumber,
        isrc,
        sourceUrl,
        providerId,
      );
}

/// One answer a `SwayveMetadataSearchProvider` gives to a
/// [SwayveMetadataQuery], or to a resolved URL.
///
/// This is not [SwayveTrack]: a metadata candidate need not be playable, and
/// the host never plays it directly — it is offered to the person as a fact
/// about a song, and only the fields they accept become a correction on
/// their own copy. [title] is the only thing every candidate must carry.
@immutable
final class SwayveMetadataCandidate {
  /// Creates a candidate.
  const SwayveMetadataCandidate({
    required this.title,
    this.providerItemId,
    this.artists = const [],
    this.album,
    this.year,
    this.duration,
    this.artwork,
    this.isrc,
    this.sourceUrl,
    this.extra = const {},
  });

  /// This provider's own id for the item, when it has one — an id the host
  /// may hand back as [SwayveMetadataQuery.providerId] on a later lookup.
  final String? providerItemId;

  /// The title as this provider spells it. Never empty.
  final String title;

  /// Credited artists, in credit order.
  final List<String> artists;

  /// The album this candidate belongs to, when it has one.
  final String? album;

  /// The release year, when known.
  final int? year;

  /// The playing time, when known — the single most useful signal for
  /// telling two versions of the same song apart.
  final Duration? duration;

  /// A URL to the artwork image, when this provider has one.
  final Uri? artwork;

  /// The International Standard Recording Code, when this provider has one.
  final String? isrc;

  /// Where a person could view this on the provider's own service.
  final Uri? sourceUrl;

  /// Provider-specific data the host never interprets. Must be
  /// JSON-encodable, since the host may persist it alongside the candidate
  /// while someone decides whether to apply it.
  final Map<String, Object?> extra;

  /// Returns a copy with the given fields replaced.
  SwayveMetadataCandidate copyWith({
    String? providerItemId,
    String? title,
    List<String>? artists,
    String? album,
    int? year,
    Duration? duration,
    Uri? artwork,
    String? isrc,
    Uri? sourceUrl,
    Map<String, Object?>? extra,
  }) =>
      SwayveMetadataCandidate(
        providerItemId: providerItemId ?? this.providerItemId,
        title: title ?? this.title,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        year: year ?? this.year,
        duration: duration ?? this.duration,
        artwork: artwork ?? this.artwork,
        isrc: isrc ?? this.isrc,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        extra: extra ?? this.extra,
      );

  /// The wire form. Null fields are omitted; [duration] is milliseconds.
  Map<String, Object?> toJson() => pruneNulls({
        'providerItemId': providerItemId,
        'title': title,
        'artists': artists.isEmpty ? null : artists,
        'album': album,
        'year': year,
        'durationMs': durationToJson(duration),
        'artwork': artwork?.toString(),
        'isrc': isrc,
        'sourceUrl': sourceUrl?.toString(),
        'extra': extra.isEmpty ? null : extra,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveMetadataCandidate fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveMetadataCandidate', json);
    return SwayveMetadataCandidate(
      providerItemId: reader.stringOrNull('providerItemId'),
      title: reader.string('title'),
      artists: reader.stringList('artists'),
      album: reader.stringOrNull('album'),
      year: reader.integerOrNull('year'),
      duration: reader.durationOrNull('durationMs'),
      artwork: reader.uriOrNull('artwork'),
      isrc: reader.stringOrNull('isrc'),
      sourceUrl: reader.uriOrNull('sourceUrl'),
      extra: reader.extra('extra'),
    );
  }

  @override
  String toString() => 'SwayveMetadataCandidate($title, $artists)';

  @override
  bool operator ==(Object other) =>
      other is SwayveMetadataCandidate &&
      providerItemId == other.providerItemId &&
      title == other.title &&
      deepEquals(artists, other.artists) &&
      album == other.album &&
      year == other.year &&
      duration == other.duration &&
      artwork == other.artwork &&
      isrc == other.isrc &&
      sourceUrl == other.sourceUrl &&
      deepEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(
        providerItemId,
        title,
        deepHash(artists),
        album,
        year,
        duration,
        artwork,
        isrc,
        sourceUrl,
        deepHash(extra),
      );
}
