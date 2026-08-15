import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';
import 'image_ref.dart';
import 'media_id.dart';

/// A performer or group, normalized across every provider.
///
/// As with albums, Swayve's own `Artist` is derived from the tracks it holds
/// rather than stored, so surfacing a plugin artist is host work beyond the
/// mapping itself.
@immutable
final class SwayveArtist {
  /// Creates an artist.
  const SwayveArtist({
    required this.id,
    required this.name,
    this.image,
    this.genres = const [],
    this.extra = const {},
  });

  /// The identifier the host hands back to browse this artist.
  final SwayveMediaId id;

  /// The display name. Never empty.
  final String name;

  /// A representative image, when the provider has one.
  final SwayveImageRef? image;

  /// Genre labels as the provider spells them.
  ///
  /// Free text: there is no controlled vocabulary, and the host must not
  /// assume one.
  final List<String> genres;

  /// Provider-specific data the host never interprets. Must be
  /// JSON-encodable.
  final Map<String, Object?> extra;

  /// Returns a copy with the given fields replaced.
  SwayveArtist copyWith({
    SwayveMediaId? id,
    String? name,
    SwayveImageRef? image,
    List<String>? genres,
    Map<String, Object?>? extra,
  }) =>
      SwayveArtist(
        id: id ?? this.id,
        name: name ?? this.name,
        image: image ?? this.image,
        genres: genres ?? this.genres,
        extra: extra ?? this.extra,
      );

  /// The wire form. Null and empty fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'name': name,
        'image': image?.toJson(),
        'genres': genres.isEmpty ? null : genres,
        'extra': extra.isEmpty ? null : extra,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveArtist fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveArtist', json);
    return SwayveArtist(
      id: reader.object('id', SwayveMediaId.fromJson),
      name: reader.string('name'),
      image: reader.objectOrNull('image', SwayveImageRef.fromJson),
      genres: reader.stringList('genres'),
      extra: reader.extra('extra'),
    );
  }

  @override
  String toString() => 'SwayveArtist($name, $id)';

  @override
  bool operator ==(Object other) =>
      other is SwayveArtist &&
      id == other.id &&
      name == other.name &&
      image == other.image &&
      deepEquals(genres, other.genres) &&
      deepEquals(extra, other.extra);

  @override
  int get hashCode =>
      Object.hash(id, name, image, deepHash(genres), deepHash(extra));
}
