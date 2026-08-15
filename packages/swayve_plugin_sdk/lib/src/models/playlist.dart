import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';
import 'image_ref.dart';
import 'media_id.dart';

/// An ordered, provider-owned collection of tracks.
///
/// Read-only in v1: the `playlistRead` capability lets a plugin expose
/// playlists it already has, never create or edit them. Swayve has no
/// playlist model of its own yet, so this is a forward-looking surface — a
/// plugin may implement it, and the host may not surface it until it grows a
/// place to put it.
@immutable
final class SwayvePlaylist {
  /// Creates a playlist.
  const SwayvePlaylist({
    required this.id,
    required this.title,
    this.description,
    this.ownerName,
    this.trackCount,
    this.artwork,
    this.extra = const {},
  });

  /// The identifier the host hands back to fetch this playlist's tracks.
  final SwayveMediaId id;

  /// The playlist title. Never empty.
  final String title;

  /// A short description, when the provider has one.
  final String? description;

  /// The display name of whoever owns the playlist, when known.
  final String? ownerName;

  /// How many tracks it contains, when the provider knows without fetching
  /// them.
  final int? trackCount;

  /// Cover art, when the provider has any.
  final SwayveImageRef? artwork;

  /// Provider-specific data the host never interprets. Must be
  /// JSON-encodable.
  final Map<String, Object?> extra;

  /// Returns a copy with the given fields replaced.
  SwayvePlaylist copyWith({
    SwayveMediaId? id,
    String? title,
    String? description,
    String? ownerName,
    int? trackCount,
    SwayveImageRef? artwork,
    Map<String, Object?>? extra,
  }) =>
      SwayvePlaylist(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        ownerName: ownerName ?? this.ownerName,
        trackCount: trackCount ?? this.trackCount,
        artwork: artwork ?? this.artwork,
        extra: extra ?? this.extra,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'title': title,
        'description': description,
        'ownerName': ownerName,
        'trackCount': trackCount,
        'artwork': artwork?.toJson(),
        'extra': extra.isEmpty ? null : extra,
      });

  /// Parses the wire form produced by [toJson].
  static SwayvePlaylist fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayvePlaylist', json);
    return SwayvePlaylist(
      id: reader.object('id', SwayveMediaId.fromJson),
      title: reader.string('title'),
      description: reader.stringOrNull('description'),
      ownerName: reader.stringOrNull('ownerName'),
      trackCount: reader.integerOrNull('trackCount'),
      artwork: reader.objectOrNull('artwork', SwayveImageRef.fromJson),
      extra: reader.extra('extra'),
    );
  }

  @override
  String toString() => 'SwayvePlaylist($title, $id)';

  @override
  bool operator ==(Object other) =>
      other is SwayvePlaylist &&
      id == other.id &&
      title == other.title &&
      description == other.description &&
      ownerName == other.ownerName &&
      trackCount == other.trackCount &&
      artwork == other.artwork &&
      deepEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        description,
        ownerName,
        trackCount,
        artwork,
        deepHash(extra),
      );
}
