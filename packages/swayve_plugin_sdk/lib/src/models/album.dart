import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';
import 'availability.dart';
import 'image_ref.dart';
import 'media_id.dart';
import 'refs.dart';

/// A release grouping tracks, normalized across every provider.
///
/// Note for host implementers: Swayve's own `Album` is *derived* from the
/// tracks it has, not stored. A plugin album therefore has to be projected
/// through its tracks or given a construction path of its own — the mapping
/// is not one-to-one, and that is host work, not plugin work.
@immutable
final class SwayveAlbum {
  /// Creates an album.
  const SwayveAlbum({
    required this.id,
    required this.title,
    this.artists = const [],
    this.year,
    this.trackCount,
    this.artwork,
    this.availability = SwayveAvailability.none,
    this.extra = const {},
  });

  /// The identifier the host hands back to fetch this album's tracks.
  final SwayveMediaId id;

  /// The release title. Never empty.
  final String title;

  /// The credited album artists, in credit order.
  final List<SwayveArtistRef> artists;

  /// The release year, when known.
  final int? year;

  /// How many tracks the release has, when the provider knows without
  /// fetching them.
  final int? trackCount;

  /// Cover art, when the provider has any.
  final SwayveImageRef? artwork;

  /// What may be done with the release as a whole. Individual tracks may
  /// still differ; the host reads each track's own availability before
  /// playing it.
  final SwayveAvailability availability;

  /// Provider-specific data the host never interprets. Must be
  /// JSON-encodable.
  final Map<String, Object?> extra;

  /// The artists' names joined for display, in credit order.
  String get artistsLabel => artists.map((ref) => ref.name).join(', ');

  /// Returns a copy with the given fields replaced.
  SwayveAlbum copyWith({
    SwayveMediaId? id,
    String? title,
    List<SwayveArtistRef>? artists,
    int? year,
    int? trackCount,
    SwayveImageRef? artwork,
    SwayveAvailability? availability,
    Map<String, Object?>? extra,
  }) =>
      SwayveAlbum(
        id: id ?? this.id,
        title: title ?? this.title,
        artists: artists ?? this.artists,
        year: year ?? this.year,
        trackCount: trackCount ?? this.trackCount,
        artwork: artwork ?? this.artwork,
        availability: availability ?? this.availability,
        extra: extra ?? this.extra,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'title': title,
        'artists': artists.map((ref) => ref.toJson()).toList(),
        'year': year,
        'trackCount': trackCount,
        'artwork': artwork?.toJson(),
        'availability': availability.toJson(),
        'extra': extra.isEmpty ? null : extra,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveAlbum fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveAlbum', json);
    return SwayveAlbum(
      id: reader.object('id', SwayveMediaId.fromJson),
      title: reader.string('title'),
      artists: reader.objectList('artists', SwayveArtistRef.fromJson),
      year: reader.integerOrNull('year'),
      trackCount: reader.integerOrNull('trackCount'),
      artwork: reader.objectOrNull('artwork', SwayveImageRef.fromJson),
      availability: reader.has('availability')
          ? reader.object('availability', SwayveAvailability.fromJson)
          : SwayveAvailability.none,
      extra: reader.extra('extra'),
    );
  }

  @override
  String toString() => 'SwayveAlbum($title by $artistsLabel, $id)';

  @override
  bool operator ==(Object other) =>
      other is SwayveAlbum &&
      id == other.id &&
      title == other.title &&
      deepEquals(artists, other.artists) &&
      year == other.year &&
      trackCount == other.trackCount &&
      artwork == other.artwork &&
      availability == other.availability &&
      deepEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        deepHash(artists),
        year,
        trackCount,
        artwork,
        availability,
        deepHash(extra),
      );
}
