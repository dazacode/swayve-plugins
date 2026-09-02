import 'package:meta/meta.dart';

import '../enums.dart';
import '../internal/equality.dart';
import '../internal/json.dart';
import 'album.dart';
import 'image_ref.dart';
import 'media_id.dart';
import 'playlist.dart';
import 'track.dart';

/// A performer or group, normalized across every provider.
///
/// As with albums, Swayve's own `Artist` is derived from the tracks it holds
/// rather than stored, so surfacing a plugin artist is host work beyond the
/// mapping itself.
///
/// The model carries two quite different amounts of information depending on
/// where it came from, and the difference is deliberate. A *listing* — a search
/// result, a "fans might also like" shelf, a browse feed — mints an artist out
/// of one tile: an id, a name and a picture, and nothing else, because that is
/// all the tile said. A *lookup* (`SwayveCatalogProvider.artist`) fetches the
/// artist's own page and can fill in everything below. Nothing here is required
/// for that reason: every field a page carries is one a tile does not, and a
/// host drawing either has to cope with the thin form.
///
/// The counts are deliberately [String]s. See [subscriberLabel].
@immutable
final class SwayveArtist {
  /// Creates an artist.
  const SwayveArtist({
    required this.id,
    required this.name,
    this.image,
    this.banner,
    this.description,
    this.subscriberLabel,
    this.monthlyListenerLabel,
    this.playAll,
    this.startRadio,
    this.genres = const [],
    this.sections = const [],
    this.extra = const {},
  });

  /// The identifier the host hands back to browse this artist.
  final SwayveMediaId id;

  /// The display name. Never empty.
  final String name;

  /// A representative image, when the provider has one.
  ///
  /// The artist as a person: a portrait, an avatar, a band photograph — the
  /// picture a service draws in a circle beside the name. Squarish, and safe to
  /// crop to a circle. [banner] is the other one.
  final SwayveImageRef? image;

  /// A wide header image, when the provider publishes one.
  ///
  /// Separate from [image] rather than a second entry in a list, because the
  /// two are not interchangeable and a host that picked between them by size
  /// would get both jobs wrong: a 2560×424 banner cropped to a circle is a
  /// sliver of somebody's shoulder, and a square portrait stretched across a
  /// page header is a blurred mess. A host that has only one of the two should
  /// draw the surface the other would have filled some other way — usually by
  /// blurring what it does have — rather than substituting.
  final SwayveImageRef? banner;

  /// A biography or blurb, as the provider wrote it.
  ///
  /// Plain text, in whatever language the provider answered in. Not markup: a
  /// host renders it as text and must not be asked to parse anything.
  final String? description;

  /// How many people follow this artist, as the provider chose to say it.
  ///
  /// A [String] and not an [int], and that is the honest shape rather than a
  /// missing parse. Services publish this as display text — `1.2M subscribers`,
  /// `1,2 M d'abonnés` — already abbreviated and already localized to the
  /// market the request was made from, and the exact number is not in the
  /// payload at all. A plugin turning `1.2M` back into `1200000` would be
  /// inventing three digits of precision the service never stated, and the host
  /// would then re-abbreviate the invention.
  ///
  /// So the label travels verbatim, including the word "subscribers" or its
  /// translation, and the host draws it as-is. A host that wants its own
  /// phrasing has no way to get one; that is a real limitation and the
  /// alternative is a fabricated number.
  final String? subscriberLabel;

  /// How many people listened this month, as the provider chose to say it.
  ///
  /// The same reasoning as [subscriberLabel], and a different fact: followers
  /// are an accumulated total and monthly listeners are a rolling measure of
  /// how much the artist is actually being played right now. Services that
  /// publish both publish them separately, and a host showing one in place of
  /// the other would be showing a different statistic under the same word.
  final String? monthlyListenerLabel;

  /// A collection that plays this artist's music, when the provider offers one.
  ///
  /// What sits behind the play button on the artist's own page: an id the host
  /// hands to whichever provider owns it — a playlist to
  /// `SwayvePlaylistProvider`, an album to `SwayveCatalogProvider` — exactly as
  /// it would with an id from anywhere else. It is not derivable from
  /// [sections]: a top-songs shelf is the ten songs a page had room for, while
  /// this is the whole catalogue in the order the service would play it.
  ///
  /// No separate `shuffle` field. Shuffling is the host's own transport
  /// concern — it already owns the queue and a shuffle toggle — so a second id
  /// meaning "the same collection, unordered" would be the host asking the
  /// plugin's permission to use its own control.
  final SwayveMediaId? playAll;

  /// A station seeded on this artist, when the provider offers one.
  ///
  /// Handed to `SwayveRadioProvider.radioTracks` the same way
  /// `SwayveRadio.id` is. Distinct from [playAll] in the way a radio is always
  /// distinct from a playlist: this one has no end, and it reaches past the
  /// artist's own catalogue into whatever the service thinks sounds like them.
  final SwayveMediaId? startRadio;

  /// Genre labels as the provider spells them.
  ///
  /// Free text: there is no controlled vocabulary, and the host must not
  /// assume one.
  final List<String> genres;

  /// The shelves of the artist's own page, in the order the provider put them.
  ///
  /// Empty from a listing, for the reason given on the class: a tile in a
  /// search result describes an artist and does not carry their discography.
  /// Populated by `SwayveCatalogProvider.artist`, which is the call a host
  /// makes when somebody opens one.
  ///
  /// This is the field that stops a host reconstructing an artist page out of
  /// whatever it happens to hold. A host that guesses gets it wrong in a way
  /// nothing downstream can fix: the songs it lists are the ones already in the
  /// library sorted by title rather than the ones the service says are this
  /// artist's biggest, and every release nobody has played yet is simply
  /// absent. Order is preserved because it is editorial — a service leads with
  /// top songs and closes with related artists on purpose, and re-sorting the
  /// shelves alphabetically would throw that away.
  final List<SwayveArtistSection> sections;

  /// Provider-specific data the host never interprets. Must be
  /// JSON-encodable.
  final Map<String, Object?> extra;

  /// Returns a copy with the given fields replaced.
  SwayveArtist copyWith({
    SwayveMediaId? id,
    String? name,
    SwayveImageRef? image,
    SwayveImageRef? banner,
    String? description,
    String? subscriberLabel,
    String? monthlyListenerLabel,
    SwayveMediaId? playAll,
    SwayveMediaId? startRadio,
    List<String>? genres,
    List<SwayveArtistSection>? sections,
    Map<String, Object?>? extra,
  }) =>
      SwayveArtist(
        id: id ?? this.id,
        name: name ?? this.name,
        image: image ?? this.image,
        banner: banner ?? this.banner,
        description: description ?? this.description,
        subscriberLabel: subscriberLabel ?? this.subscriberLabel,
        monthlyListenerLabel: monthlyListenerLabel ?? this.monthlyListenerLabel,
        playAll: playAll ?? this.playAll,
        startRadio: startRadio ?? this.startRadio,
        genres: genres ?? this.genres,
        sections: sections ?? this.sections,
        extra: extra ?? this.extra,
      );

  /// The wire form. Null and empty fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'id': id.toJson(),
        'name': name,
        'image': image?.toJson(),
        'banner': banner?.toJson(),
        'description': description,
        'subscriberLabel': subscriberLabel,
        'monthlyListenerLabel': monthlyListenerLabel,
        'playAll': playAll?.toJson(),
        'startRadio': startRadio?.toJson(),
        'genres': genres.isEmpty ? null : genres,
        'sections': sections.isEmpty
            ? null
            : sections.map((section) => section.toJson()).toList(),
        'extra': extra.isEmpty ? null : extra,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveArtist fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveArtist', json);
    return SwayveArtist(
      id: reader.object('id', SwayveMediaId.fromJson),
      name: reader.string('name'),
      image: reader.objectOrNull('image', SwayveImageRef.fromJson),
      banner: reader.objectOrNull('banner', SwayveImageRef.fromJson),
      description: reader.stringOrNull('description'),
      subscriberLabel: reader.stringOrNull('subscriberLabel'),
      monthlyListenerLabel: reader.stringOrNull('monthlyListenerLabel'),
      playAll: reader.objectOrNull('playAll', SwayveMediaId.fromJson),
      startRadio: reader.objectOrNull('startRadio', SwayveMediaId.fromJson),
      genres: reader.stringList('genres'),
      sections: reader.objectList('sections', SwayveArtistSection.fromJson),
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
      banner == other.banner &&
      description == other.description &&
      subscriberLabel == other.subscriberLabel &&
      monthlyListenerLabel == other.monthlyListenerLabel &&
      playAll == other.playAll &&
      startRadio == other.startRadio &&
      deepEquals(genres, other.genres) &&
      deepEquals(sections, other.sections) &&
      deepEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        image,
        banner,
        description,
        subscriberLabel,
        monthlyListenerLabel,
        playAll,
        startRadio,
        deepHash(genres),
        deepHash(sections),
        deepHash(extra),
      );
}

/// One titled shelf of an artist's page.
///
/// Four lists rather than one list of a common supertype, which is the same
/// shape `SwayveSearchResult` settled on and for the same reason: there is no
/// supertype. A track, an album and a playlist share no field a host would draw
/// them by, so a `List<Object>` would only push the type test into every call
/// site and lose static typing on the way. A shelf populates exactly one of the
/// four in practice — services do not mix entity types within a row — but that
/// is a fact about the services rather than something enforced here, and a
/// provider with a genuinely mixed shelf can express it rather than having to
/// split or drop it.
///
/// [kind] is what a host lays the page out by; [title] is what it prints.
/// Reading the layout off the title instead is the mistake the enum's own
/// documentation exists to prevent.
@immutable
final class SwayveArtistSection {
  /// Creates a section.
  const SwayveArtistSection({
    required this.kind,
    this.title,
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.more,
  });

  /// What this shelf is a shelf of. The host lays out by this, never by
  /// [title].
  final SwayveArtistSectionKind kind;

  /// The shelf heading in the provider's own words, when it had one.
  ///
  /// For display only, and localized to whatever market the request was made
  /// from. A host with no title of its own to fall back on can print this; a
  /// host that would rather phrase its own headings should, since it knows the
  /// user's language and the provider only knows the request's.
  final String? title;

  /// Tracks on this shelf, in provider order.
  ///
  /// Order is the ranking for [SwayveArtistSectionKind.topSongs] — first is
  /// biggest — and must not be re-sorted before it is drawn.
  final List<SwayveTrack> tracks;

  /// Releases on this shelf, in provider order.
  final List<SwayveAlbum> albums;

  /// Artists on this shelf, in provider order.
  final List<SwayveArtist> artists;

  /// Playlists on this shelf, in provider order.
  final List<SwayvePlaylist> playlists;

  /// The full listing this shelf is an excerpt of, when the provider offers
  /// one.
  ///
  /// A shelf shows the handful a page had room for and a service usually has a
  /// whole page behind it — every album rather than the six most recent. This
  /// is the id of that page, and a host that has somewhere to send it may draw
  /// a "see all".
  ///
  /// It is honestly a forward-looking field. In API level 1 the host's only
  /// entry points take an album, an artist or a playlist id, and a
  /// discography-style listing is none of the three — so for most providers
  /// there is currently nowhere to send it. It is carried anyway rather than
  /// discarded at the parser, because the id costs nothing to keep and cannot
  /// be recovered later without re-fetching the page it came from.
  final SwayveMediaId? more;

  /// Whether the shelf holds nothing at all.
  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  /// Returns a copy with the given fields replaced.
  SwayveArtistSection copyWith({
    SwayveArtistSectionKind? kind,
    String? title,
    List<SwayveTrack>? tracks,
    List<SwayveAlbum>? albums,
    List<SwayveArtist>? artists,
    List<SwayvePlaylist>? playlists,
    SwayveMediaId? more,
  }) =>
      SwayveArtistSection(
        kind: kind ?? this.kind,
        title: title ?? this.title,
        tracks: tracks ?? this.tracks,
        albums: albums ?? this.albums,
        artists: artists ?? this.artists,
        playlists: playlists ?? this.playlists,
        more: more ?? this.more,
      );

  /// The wire form. Null and empty fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'kind': kind.wireName,
        'title': title,
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
        'more': more?.toJson(),
      });

  /// Parses the wire form produced by [toJson].
  static SwayveArtistSection fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveArtistSection', json);
    return SwayveArtistSection(
      kind: reader.enumValue('kind', SwayveArtistSectionKind.fromWire),
      title: reader.stringOrNull('title'),
      tracks: reader.objectList('tracks', SwayveTrack.fromJson),
      albums: reader.objectList('albums', SwayveAlbum.fromJson),
      artists: reader.objectList('artists', SwayveArtist.fromJson),
      playlists: reader.objectList('playlists', SwayvePlaylist.fromJson),
      more: reader.objectOrNull('more', SwayveMediaId.fromJson),
    );
  }

  @override
  String toString() => 'SwayveArtistSection(${kind.wireName}, "$title", '
      'tracks: ${tracks.length}, albums: ${albums.length}, '
      'artists: ${artists.length}, playlists: ${playlists.length})';

  @override
  bool operator ==(Object other) =>
      other is SwayveArtistSection &&
      kind == other.kind &&
      title == other.title &&
      deepEquals(tracks, other.tracks) &&
      deepEquals(albums, other.albums) &&
      deepEquals(artists, other.artists) &&
      deepEquals(playlists, other.playlists) &&
      more == other.more;

  @override
  int get hashCode => Object.hash(
        kind,
        title,
        deepHash(tracks),
        deepHash(albums),
        deepHash(artists),
        deepHash(playlists),
        more,
      );
}
