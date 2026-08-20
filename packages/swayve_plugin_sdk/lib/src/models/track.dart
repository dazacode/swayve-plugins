import 'package:meta/meta.dart';

import '../enums.dart';
import '../internal/equality.dart';
import '../internal/json.dart';
import 'alternate_names.dart';
import 'availability.dart';
import 'image_ref.dart';
import 'media_id.dart';
import 'refs.dart';

/// A single playable piece of music, normalized across every provider.
///
/// This is the type the host's own `Track` is mapped from. A provider fills
/// in what it knows and leaves the rest null — the host never treats a null
/// optional field as an error, only as an absent fact.
///
/// Two invariants an implementer must hold:
/// * [id] is stable for the same item across calls and across app restarts,
///   because the host persists it;
/// * [availability] states the three facts of principle 6 truthfully; the
///   host will believe it.
@immutable
final class SwayveTrack {
  /// Creates a track.
  const SwayveTrack({
    required this.id,
    required this.title,
    this.artists = const [],
    this.album,
    this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.artwork,
    this.explicit = false,
    this.availability = SwayveAvailability.none,
    this.kind = SwayveTrackKind.song,
    this.extra = const {},
    this.externalUrl,
    this.alternateNames = SwayveAlternateNames.none,
  });

  /// The identifier the host will hand back to ask for playback or details.
  final SwayveMediaId id;

  /// The track title as the provider spells it. Never empty.
  final String title;

  /// The credited artists, in credit order.
  ///
  /// Never a bare string: see [SwayveArtistRef]. May be empty when the
  /// provider genuinely has no artist information.
  final List<SwayveArtistRef> artists;

  /// The album this track belongs to, when it belongs to one.
  final SwayveAlbumRef? album;

  /// The playing time, when known.
  final Duration? duration;

  /// The track's position within its disc, 1-based, when known.
  final int? trackNumber;

  /// The disc number within a multi-disc release, 1-based, when known.
  final int? discNumber;

  /// The release year, when known.
  final int? year;

  /// Track-level artwork, when it differs from the album's or when no album
  /// is known.
  final SwayveImageRef? artwork;

  /// Whether the provider marks this recording as explicit.
  final bool explicit;

  /// What may be done with this track. See principle 6.
  final SwayveAvailability availability;

  /// What this recording is, when the provider draws that distinction.
  ///
  /// Defaults to [SwayveTrackKind.song], which claims nothing beyond "a
  /// recording" — see the enum. A host may use it to separate a service's
  /// licensed catalogue from its uploads; a host that ignores it gets one
  /// correct list.
  final SwayveTrackKind kind;

  /// Provider-specific data the host never interprets.
  ///
  /// It is carried along and handed back to the plugin unchanged, so a plugin
  /// may use it to avoid a second lookup. It must be JSON-encodable, because
  /// the host may persist it.
  final Map<String, Object?> extra;

  /// Where a person, not the host, can view this track on the provider's own
  /// service — its page on soundcloud.com, its watch page on
  /// music.youtube.com. Not the [availability]/stream address a host plays
  /// from, and not stable in the way [id] must be: a host may show this to
  /// someone as "view on the service" or offer to copy it, and nothing else.
  final Uri? externalUrl;

  /// The other names this recording, its credit and its release go by, as the
  /// provider publishes them.
  ///
  /// [title] stays canonical and is never any of these. A provider that holds a
  /// romanization or a translation puts it here beside the title rather than in
  /// place of it, because a host that overwrote the title with a romanization
  /// would have destroyed the only name the record actually has, and no display
  /// preference switched back afterwards would return it.
  ///
  /// Defaults to [SwayveAlternateNames.none], which is what the overwhelming
  /// majority of tracks and every provider that predates the field carry.
  final SwayveAlternateNames alternateNames;

  /// The artists' names joined for display, in credit order.
  ///
  /// Provided because the host's own model is single-artist; using this
  /// keeps every plugin's joining behaviour identical.
  String get artistsLabel => artists.map((ref) => ref.name).join(', ');

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` for a field keeps the current value; construct a new
  /// track to clear an optional field.
  SwayveTrack copyWith({
    SwayveMediaId? id,
    String? title,
    List<SwayveArtistRef>? artists,
    SwayveAlbumRef? album,
    Duration? duration,
    int? trackNumber,
    int? discNumber,
    int? year,
    SwayveImageRef? artwork,
    bool? explicit,
    SwayveAvailability? availability,
    SwayveTrackKind? kind,
    Map<String, Object?>? extra,
    Uri? externalUrl,
    SwayveAlternateNames? alternateNames,
  }) =>
      SwayveTrack(
        id: id ?? this.id,
        title: title ?? this.title,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        trackNumber: trackNumber ?? this.trackNumber,
        discNumber: discNumber ?? this.discNumber,
        year: year ?? this.year,
        artwork: artwork ?? this.artwork,
        explicit: explicit ?? this.explicit,
        availability: availability ?? this.availability,
        kind: kind ?? this.kind,
        extra: extra ?? this.extra,
        externalUrl: externalUrl ?? this.externalUrl,
        alternateNames: alternateNames ?? this.alternateNames,
      );

  /// The wire form. Null fields are omitted; [duration] is milliseconds.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'title': title,
        'artists': artists.map((ref) => ref.toJson()).toList(),
        'album': album?.toJson(),
        'durationMs': durationToJson(duration),
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'year': year,
        'artwork': artwork?.toJson(),
        'explicit': explicit,
        'availability': availability.toJson(),
        'kind': kind.wireName,
        'extra': extra.isEmpty ? null : extra,
        'externalUrl': externalUrl?.toString(),
        'alternateNames':
            alternateNames.isEmpty ? null : alternateNames.toJson(),
      });

  /// Parses the wire form produced by [toJson].
  static SwayveTrack fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveTrack', json);
    return SwayveTrack(
      id: reader.object('id', SwayveMediaId.fromJson),
      title: reader.string('title'),
      artists: reader.objectList('artists', SwayveArtistRef.fromJson),
      album: reader.objectOrNull('album', SwayveAlbumRef.fromJson),
      duration: reader.durationOrNull('durationMs'),
      trackNumber: reader.integerOrNull('trackNumber'),
      discNumber: reader.integerOrNull('discNumber'),
      year: reader.integerOrNull('year'),
      artwork: reader.objectOrNull('artwork', SwayveImageRef.fromJson),
      explicit: reader.boolean('explicit'),
      availability: reader.has('availability')
          ? reader.object('availability', SwayveAvailability.fromJson)
          : SwayveAvailability.none,
      // An unreadable or absent kind reads as `song`. A provider that predates
      // the field, and one built against a later SDK that names something this
      // host has never heard of, are the same case: the recording is still a
      // recording, and losing it over a label it happens to carry would be the
      // worse answer.
      kind: SwayveTrackKind.fromWire(json['kind'] as String? ?? '') ??
          SwayveTrackKind.song,
      extra: reader.extra('extra'),
      externalUrl: reader.uriOrNull('externalUrl'),
      alternateNames: reader.objectOrNull(
            'alternateNames',
            SwayveAlternateNames.fromJson,
          ) ??
          SwayveAlternateNames.none,
    );
  }

  @override
  String toString() => 'SwayveTrack($title by $artistsLabel, $id)';

  @override
  bool operator ==(Object other) =>
      other is SwayveTrack &&
      id == other.id &&
      title == other.title &&
      deepEquals(artists, other.artists) &&
      album == other.album &&
      duration == other.duration &&
      trackNumber == other.trackNumber &&
      discNumber == other.discNumber &&
      year == other.year &&
      artwork == other.artwork &&
      explicit == other.explicit &&
      availability == other.availability &&
      kind == other.kind &&
      deepEquals(extra, other.extra) &&
      externalUrl == other.externalUrl &&
      alternateNames == other.alternateNames;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        deepHash(artists),
        album,
        duration,
        trackNumber,
        discNumber,
        year,
        artwork,
        explicit,
        availability,
        kind,
        deepHash(extra),
        externalUrl,
        alternateNames,
      );
}
