import 'package:meta/meta.dart';

import '../internal/json.dart';
import 'media_id.dart';

/// One play, reported to an external listening-history service.
///
/// This is deliberately flat and self-contained rather than carrying a
/// `SwayveTrack`: the play may be of a track the reporting plugin did not
/// supply — Swayve scrobbles local files too — so the fields are the plain
/// strings every scrobbling service expects.
@immutable
final class SwayveScrobble {
  /// Creates a scrobble.
  const SwayveScrobble({
    required this.id,
    required this.title,
    required this.artist,
    required this.playedAt,
    this.album,
    this.duration,
  });

  /// The identifier of what was played.
  ///
  /// For a track from another source this is that source's id; a scrobble
  /// provider must not assume it can resolve it.
  final SwayveMediaId id;

  /// The track title as it should be reported.
  final String title;

  /// The artist as it should be reported, already joined for display when
  /// the source had several.
  final String artist;

  /// The album title, when known.
  final String? album;

  /// The track's length, when known. Some services reject a scrobble without
  /// it.
  final Duration? duration;

  /// When the play started, in UTC.
  ///
  /// The host stamps this, not the plugin, so that a queued scrobble
  /// submitted late still reports the true listening time.
  final DateTime playedAt;

  /// Returns a copy with the given fields replaced.
  SwayveScrobble copyWith({
    SwayveMediaId? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    DateTime? playedAt,
  }) =>
      SwayveScrobble(
        id: id ?? this.id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        playedAt: playedAt ?? this.playedAt,
      );

  /// The wire form. [playedAt] is an ISO-8601 UTC timestamp.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationToJson(duration),
        'playedAt': playedAt.toUtc().toIso8601String(),
      });

  /// Parses the wire form produced by [toJson].
  static SwayveScrobble fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveScrobble', json);
    return SwayveScrobble(
      id: reader.object('id', SwayveMediaId.fromJson),
      title: reader.string('title'),
      artist: reader.string('artist'),
      album: reader.stringOrNull('album'),
      duration: reader.durationOrNull('durationMs'),
      playedAt: reader.dateTime('playedAt'),
    );
  }

  @override
  String toString() => 'SwayveScrobble($title by $artist at $playedAt)';

  @override
  bool operator ==(Object other) =>
      other is SwayveScrobble &&
      id == other.id &&
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      duration == other.duration &&
      playedAt.isAtSameMomentAs(other.playedAt);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        artist,
        album,
        duration,
        playedAt.toUtc().microsecondsSinceEpoch,
      );
}
