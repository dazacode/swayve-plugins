import 'package:meta/meta.dart';

import '../enums.dart';
import '../internal/equality.dart';
import '../internal/json.dart';
import 'album.dart';
import 'artist.dart';
import 'playlist.dart';
import 'track.dart';

/// What the host is asking a search provider to look for.
///
/// A provider must honour [kinds] — returning albums when only tracks were
/// asked for wastes the user's bandwidth — and must treat [limit] as a
/// ceiling per kind, not a total.
@immutable
final class SwayveSearchQuery {
  /// Creates a query for [text].
  const SwayveSearchQuery({
    required this.text,
    this.kinds = allKinds,
    this.limit = 20,
    this.cursor,
  });

  /// Every kind of entity a search can return.
  static const Set<SwayveSearchKind> allKinds = {
    SwayveSearchKind.track,
    SwayveSearchKind.album,
    SwayveSearchKind.artist,
    SwayveSearchKind.playlist,
  };

  /// The user's raw query text, unmodified.
  ///
  /// The host does not tokenize, stem or otherwise pre-process it: providers
  /// know their own service's query syntax and the host does not.
  final String text;

  /// Which kinds of result the caller wants. Never empty.
  final Set<SwayveSearchKind> kinds;

  /// The maximum number of results per kind.
  final int limit;

  /// An opaque continuation token from a previous [SwayveSearchResult], or
  /// `null` for the first page.
  final String? cursor;

  /// Returns a copy with the given fields replaced.
  SwayveSearchQuery copyWith({
    String? text,
    Set<SwayveSearchKind>? kinds,
    int? limit,
    String? cursor,
  }) =>
      SwayveSearchQuery(
        text: text ?? this.text,
        kinds: kinds ?? this.kinds,
        limit: limit ?? this.limit,
        cursor: cursor ?? this.cursor,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'text': text,
        'kinds': kinds.map((kind) => kind.wireName).toList(),
        'limit': limit,
        'cursor': cursor,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveSearchQuery fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveSearchQuery', json);
    final kinds = reader.enumSet('kinds', SwayveSearchKind.fromWire);
    return SwayveSearchQuery(
      text: reader.string('text'),
      kinds: kinds.isEmpty ? allKinds : kinds,
      limit: reader.integerOrNull('limit') ?? 20,
      cursor: reader.stringOrNull('cursor'),
    );
  }

  @override
  String toString() => 'SwayveSearchQuery("$text", kinds: $kinds)';

  @override
  bool operator ==(Object other) =>
      other is SwayveSearchQuery &&
      text == other.text &&
      deepEquals(kinds, other.kinds) &&
      limit == other.limit &&
      cursor == other.cursor;

  @override
  int get hashCode => Object.hash(text, deepHash(kinds), limit, cursor);
}

/// Everything one provider found for one query.
///
/// A provider returns a result even when it found nothing; it throws only
/// when it could not search at all. That distinction is what lets the host
/// tell "no matches" apart from "this source is down".
@immutable
final class SwayveSearchResult {
  /// Creates a result. Every list defaults to empty.
  const SwayveSearchResult({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.cursor,
    this.partial = false,
  });

  /// An empty result: the provider searched and found nothing.
  static const SwayveSearchResult empty = SwayveSearchResult();

  /// Matching tracks, best first.
  final List<SwayveTrack> tracks;

  /// Matching albums, best first.
  final List<SwayveAlbum> albums;

  /// Matching artists, best first.
  final List<SwayveArtist> artists;

  /// Matching playlists, best first.
  final List<SwayvePlaylist> playlists;

  /// An opaque token that fetches the next page, or `null` when there is no
  /// more to fetch.
  final String? cursor;

  /// Whether the provider truncated or degraded these results.
  ///
  /// Set it when part of the search failed, timed out, or was skipped — for
  /// example when only two of three upstream endpoints answered. The host
  /// may show the results with a "some results may be missing" hint instead
  /// of pretending the list is complete.
  final bool partial;

  /// Whether any list holds at least one item.
  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  /// Whether another page can be fetched with [cursor].
  bool get hasMore => cursor != null;

  /// Returns a copy with the given fields replaced.
  SwayveSearchResult copyWith({
    List<SwayveTrack>? tracks,
    List<SwayveAlbum>? albums,
    List<SwayveArtist>? artists,
    List<SwayvePlaylist>? playlists,
    String? cursor,
    bool? partial,
  }) =>
      SwayveSearchResult(
        tracks: tracks ?? this.tracks,
        albums: albums ?? this.albums,
        artists: artists ?? this.artists,
        playlists: playlists ?? this.playlists,
        cursor: cursor ?? this.cursor,
        partial: partial ?? this.partial,
      );

  /// The wire form. Empty lists and null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'tracks': tracks.isEmpty
            ? null
            : tracks.map((track) => track.toJson()).toList(),
        'albums': albums.isEmpty
            ? null
            : albums.map((album) => album.toJson()).toList(),
        'artists': artists.isEmpty
            ? null
            : artists.map((artist) => artist.toJson()).toList(),
        'playlists': playlists.isEmpty
            ? null
            : playlists.map((playlist) => playlist.toJson()).toList(),
        'cursor': cursor,
        'partial': partial,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveSearchResult fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveSearchResult', json);
    return SwayveSearchResult(
      tracks: reader.objectList('tracks', SwayveTrack.fromJson),
      albums: reader.objectList('albums', SwayveAlbum.fromJson),
      artists: reader.objectList('artists', SwayveArtist.fromJson),
      playlists: reader.objectList('playlists', SwayvePlaylist.fromJson),
      cursor: reader.stringOrNull('cursor'),
      partial: reader.boolean('partial'),
    );
  }

  @override
  String toString() => 'SwayveSearchResult(tracks: ${tracks.length}, '
      'albums: ${albums.length}, artists: ${artists.length}, '
      'playlists: ${playlists.length}, partial: $partial)';

  @override
  bool operator ==(Object other) =>
      other is SwayveSearchResult &&
      deepEquals(tracks, other.tracks) &&
      deepEquals(albums, other.albums) &&
      deepEquals(artists, other.artists) &&
      deepEquals(playlists, other.playlists) &&
      cursor == other.cursor &&
      partial == other.partial;

  @override
  int get hashCode => Object.hash(
        deepHash(tracks),
        deepHash(albums),
        deepHash(artists),
        deepHash(playlists),
        cursor,
        partial,
      );
}
