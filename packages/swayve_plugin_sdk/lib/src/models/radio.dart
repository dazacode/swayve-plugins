import 'package:meta/meta.dart';

import '../internal/equality.dart';
import '../internal/json.dart';
import 'image_ref.dart';
import 'media_id.dart';

/// A station a provider generated from a seed, and the handle the host pages
/// tracks out of.
///
/// Deliberately thin next to [SwayvePlaylist], and the difference is the
/// point. A playlist is a collection the service already holds: it has a
/// length, an owner, and the same contents for everybody who opens it. A
/// radio has none of those facts, because it does not exist until
/// `SwayveRadioProvider.startRadio` mints one and it has no end to measure a
/// length against — so there is no `trackCount` here and there never will be.
/// What this carries is only what a host needs to keep asking for more and to
/// draw the station while it does: an [id] to hand back, something to call it,
/// and where it came from.
@immutable
final class SwayveRadio {
  /// Creates a radio.
  const SwayveRadio({
    required this.id,
    this.title,
    this.seed,
    this.artwork,
    this.extra = const {},
  });

  /// The provider's own handle for this station, which the host hands back to
  /// `SwayveRadioProvider.radioTracks` for every page.
  ///
  /// Unlike every other [SwayveMediaId] in this SDK it need not survive an app
  /// restart: a provider that generates a station per session is free to mint
  /// an id that dies with it. A provider that *can* make it durable should,
  /// since a host that persists a queue would then be able to resume the
  /// station rather than start a new one.
  final SwayveMediaId id;

  /// What to call the station, when the provider has a name for it.
  ///
  /// Providers usually phrase this after the seed — "Radio based on <track>".
  /// Left null when the provider has nothing better than the host's own
  /// default, which is the honest answer: a host has the seed too and can
  /// phrase it in the user's own language, which a plugin cannot.
  final String? title;

  /// What the station was started from, when the provider wants to say.
  ///
  /// Ordinarily the same id handed to `startRadio`, echoed back so a host
  /// holding only the [SwayveRadio] can still say what it grew out of. A
  /// provider that expanded or substituted the seed — a track's artist stood
  /// in for the track — should report what it actually used rather than what
  /// it was asked for.
  final SwayveMediaId? seed;

  /// Cover art for the station, when the provider has any.
  final SwayveImageRef? artwork;

  /// Provider-specific data the host never interprets. Must be JSON-encodable.
  ///
  /// The natural home for whatever continuation state a service's radio
  /// endpoint wants carried between pages but does not express as a cursor.
  final Map<String, Object?> extra;

  /// Returns a copy with the given fields replaced.
  SwayveRadio copyWith({
    SwayveMediaId? id,
    String? title,
    SwayveMediaId? seed,
    SwayveImageRef? artwork,
    Map<String, Object?>? extra,
  }) =>
      SwayveRadio(
        id: id ?? this.id,
        title: title ?? this.title,
        seed: seed ?? this.seed,
        artwork: artwork ?? this.artwork,
        extra: extra ?? this.extra,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'title': title,
        'seed': seed?.toJson(),
        'artwork': artwork?.toJson(),
        'extra': extra.isEmpty ? null : extra,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveRadio fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveRadio', json);
    return SwayveRadio(
      id: reader.object('id', SwayveMediaId.fromJson),
      title: reader.stringOrNull('title'),
      seed: reader.objectOrNull('seed', SwayveMediaId.fromJson),
      artwork: reader.objectOrNull('artwork', SwayveImageRef.fromJson),
      extra: reader.extra('extra'),
    );
  }

  @override
  String toString() => 'SwayveRadio($title, $id)';

  @override
  bool operator ==(Object other) =>
      other is SwayveRadio &&
      id == other.id &&
      title == other.title &&
      seed == other.seed &&
      artwork == other.artwork &&
      deepEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(id, title, seed, artwork, deepHash(extra));
}
