import 'package:meta/meta.dart';

import '../internal/json.dart';
import 'media_id.dart';

/// A named reference to an artist, with an id when the provider has one.
///
/// Tracks and albums carry a `List<SwayveArtistRef>` rather than a bare
/// `String`, so that "Artist A & Artist B" stays two navigable entities
/// instead of one unsplittable label. A provider that genuinely only knows a
/// display name still supplies a ref — with [id] left null — so the host's
/// rendering path is the same either way.
@immutable
final class SwayveArtistRef {
  /// Creates a reference to [name], optionally identified by [id].
  const SwayveArtistRef({required this.name, this.id});

  /// The artist's identifier, when the provider can be browsed for them.
  ///
  /// `null` means "this name is all I have": the host shows the name but
  /// does not offer navigation.
  final SwayveMediaId? id;

  /// The artist's display name. Never empty.
  final String name;

  /// Returns a copy with the given fields replaced.
  SwayveArtistRef copyWith({SwayveMediaId? id, String? name}) =>
      SwayveArtistRef(id: id ?? this.id, name: name ?? this.name);

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() =>
      pruneNulls({'id': id?.toJson(), 'name': name});

  /// Parses the wire form produced by [toJson].
  static SwayveArtistRef fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveArtistRef', json);
    return SwayveArtistRef(
      id: reader.objectOrNull('id', SwayveMediaId.fromJson),
      name: reader.string('name'),
    );
  }

  @override
  String toString() => 'SwayveArtistRef($name)';

  @override
  bool operator ==(Object other) =>
      other is SwayveArtistRef && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A titled reference to an album, with an id when the provider has one.
///
/// The same reasoning as [SwayveArtistRef]: a track's album is a navigable
/// entity when the provider can serve it, and a plain label otherwise.
@immutable
final class SwayveAlbumRef {
  /// Creates a reference to [title], optionally identified by [id].
  const SwayveAlbumRef({required this.title, this.id});

  /// The album's identifier, or `null` when only the title is known.
  final SwayveMediaId? id;

  /// The album's display title. Never empty.
  final String title;

  /// Returns a copy with the given fields replaced.
  SwayveAlbumRef copyWith({SwayveMediaId? id, String? title}) =>
      SwayveAlbumRef(id: id ?? this.id, title: title ?? this.title);

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() =>
      pruneNulls({'id': id?.toJson(), 'title': title});

  /// Parses the wire form produced by [toJson].
  static SwayveAlbumRef fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveAlbumRef', json);
    return SwayveAlbumRef(
      id: reader.objectOrNull('id', SwayveMediaId.fromJson),
      title: reader.string('title'),
    );
  }

  @override
  String toString() => 'SwayveAlbumRef($title)';

  @override
  bool operator ==(Object other) =>
      other is SwayveAlbumRef && id == other.id && title == other.title;

  @override
  int get hashCode => Object.hash(id, title);
}
