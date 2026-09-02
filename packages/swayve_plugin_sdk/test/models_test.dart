import 'dart:convert';

import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

/// Encodes and decodes through real JSON, so a model that emits something
/// `jsonEncode` cannot handle fails here rather than on a device.
Map<String, Object?> roundTripJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

const SwayveMediaId trackId =
    SwayveMediaId('app.swayve.plugins.example', 't/1');
const SwayveMediaId albumId =
    SwayveMediaId('app.swayve.plugins.example', 'a 1');
const SwayveMediaId artistId =
    SwayveMediaId('app.swayve.plugins.example', 'ar?1');
const SwayveMediaId playlistId =
    SwayveMediaId('app.swayve.plugins.example', 'pl#1');

final SwayveImageRef artwork = SwayveImageRef(
  uri: Uri.parse('https://example.com/art.jpg?size=large'),
  width: 640,
  height: 640,
  blurHash: 'LEHV6nWB2yk8',
);

const SwayveArtistRef artistRef =
    SwayveArtistRef(id: artistId, name: 'Ärtist One');
const SwayveArtistRef bareArtistRef = SwayveArtistRef(name: 'Guest');
const SwayveAlbumRef albumRef = SwayveAlbumRef(id: albumId, title: 'The Album');

final SwayveTrack fullTrack = SwayveTrack(
  id: trackId,
  title: 'A Song / With Punctuation',
  artists: const [artistRef, bareArtistRef],
  album: albumRef,
  duration: const Duration(minutes: 3, seconds: 42),
  trackNumber: 4,
  discNumber: 1,
  year: 2024,
  artwork: artwork,
  explicit: true,
  availability: const SwayveAvailability(streamable: true, downloadable: true),
  extra: const {
    'sourceId': 'xyz',
    'nested': {'a': 1, 'b': null},
    'list': [1, 2, 3],
  },
  canSeedRadio: true,
);

final SwayveAlbum fullAlbum = SwayveAlbum(
  id: albumId,
  title: 'The Album',
  artists: const [artistRef],
  year: 2024,
  trackCount: 12,
  artwork: artwork,
  availability: SwayveAvailability.streamOnly,
  extra: const {'browseId': 'MPRE123'},
);

final SwayveImageRef banner = SwayveImageRef(
  uri: Uri.parse('https://example.com/banner.jpg'),
  width: 2560,
  height: 424,
);

/// An artist as a *listing* mints one: a tile's worth and nothing more.
///
/// Round-tripped alongside [fullArtist] because the thin form is the one a
/// search result and a "fans might also like" shelf actually carry, and a
/// model whose optional half is only ever exercised when it is populated is
/// half untested.
const SwayveArtist thinArtist = SwayveArtist(id: artistId, name: 'Ärtist Two');

final SwayveArtist fullArtist = SwayveArtist(
  id: artistId,
  name: 'Ärtist One',
  image: artwork,
  banner: banner,
  description: 'Formed in a garage, 2011.',
  subscriberLabel: '1.2M subscribers',
  monthlyListenerLabel: '4,203,911 monthly listeners',
  playAll: const SwayveMediaId('app.swayve.plugins.example', 'OLAK5uy_all'),
  startRadio: const SwayveMediaId('app.swayve.plugins.example', 'RDAMVMabc'),
  genres: const ['shoegaze', 'dream pop'],
  sections: [
    SwayveArtistSection(
      kind: SwayveArtistSectionKind.topSongs,
      title: 'Top songs',
      tracks: [fullTrack],
      more: const SwayveMediaId('app.swayve.plugins.example', 'more/songs'),
    ),
    SwayveArtistSection(
      kind: SwayveArtistSectionKind.singles,
      title: 'Singles',
      albums: [fullAlbum],
    ),
    const SwayveArtistSection(
      kind: SwayveArtistSectionKind.relatedArtists,
      title: 'Fans might also like',
      artists: [thinArtist],
    ),
  ],
  extra: const {'channelId': 'UC123'},
);

final SwayvePlaylist fullPlaylist = SwayvePlaylist(
  id: playlistId,
  title: 'Late Night',
  description: 'For the small hours.',
  ownerName: 'Someone',
  trackCount: 40,
  artwork: artwork,
  extra: const {'privacy': 'public'},
);

void main() {
  group('round trip through toJson/fromJson', () {
    test('SwayveMediaId', () {
      expect(SwayveMediaId.fromJson(roundTripJson(trackId.toJson())), trackId);
    });

    test('SwayveAvailability', () {
      const value = SwayveAvailability(
        streamable: true,
        downloadable: false,
        onDevice: true,
      );
      expect(
        SwayveAvailability.fromJson(roundTripJson(value.toJson())),
        value,
      );
    });

    test('SwayveImageRef', () {
      expect(
        SwayveImageRef.fromJson(roundTripJson(artwork.toJson())),
        artwork,
      );
    });

    test('SwayveImageRef with only a uri', () {
      final minimal = SwayveImageRef(uri: Uri.parse('https://x.test/a.png'));
      expect(
        SwayveImageRef.fromJson(roundTripJson(minimal.toJson())),
        minimal,
      );
    });

    test('SwayveArtistRef, with and without an id', () {
      expect(
        SwayveArtistRef.fromJson(roundTripJson(artistRef.toJson())),
        artistRef,
      );
      expect(
        SwayveArtistRef.fromJson(roundTripJson(bareArtistRef.toJson())),
        bareArtistRef,
      );
    });

    test('SwayveAlbumRef', () {
      expect(
        SwayveAlbumRef.fromJson(roundTripJson(albumRef.toJson())),
        albumRef,
      );
    });

    test('SwayveTrack, fully populated', () {
      final parsed = SwayveTrack.fromJson(roundTripJson(fullTrack.toJson()));
      expect(parsed, fullTrack);
      expect(parsed.hashCode, fullTrack.hashCode);
      expect(parsed.duration, const Duration(minutes: 3, seconds: 42));
      expect(parsed.extra['nested'], {'a': 1, 'b': null});
    });

    test('SwayveTrack, minimally populated', () {
      const minimal = SwayveTrack(id: trackId, title: 'Untitled');
      final parsed = SwayveTrack.fromJson(roundTripJson(minimal.toJson()));
      expect(parsed, minimal);
      expect(parsed.artists, isEmpty);
      expect(parsed.availability, SwayveAvailability.none);
      expect(parsed.explicit, isFalse);
      expect(
        parsed.kind,
        SwayveTrackKind.song,
        reason: 'The default claims nothing beyond "a recording" — it is not '
            'a promise that a release exists behind it.',
      );
    });

    test('SwayveTrack carries its kind across the wire', () {
      const upload = SwayveTrack(
        id: trackId,
        title: 'Nightdrive (unreleased demo)',
        kind: SwayveTrackKind.video,
      );
      final parsed = SwayveTrack.fromJson(roundTripJson(upload.toJson()));
      expect(parsed.kind, SwayveTrackKind.video);
      expect(parsed, upload);
    });

    test('a track from an older or newer provider still parses', () {
      // A provider that predates the field, and one built against a later SDK
      // naming a kind this host has never heard of, are the same case: the
      // recording is still a recording, and refusing to parse it would lose
      // the music over a label.
      for (final Object? wire in <Object?>[null, 'podcast_chapter']) {
        final json = <String, Object?>{
          ...const SwayveTrack(id: trackId, title: 'Untitled').toJson(),
          'kind': wire,
        };
        expect(SwayveTrack.fromJson(json).kind, SwayveTrackKind.song);
      }
    });

    test('SwayveMetadataQuery, fully populated', () {
      final query = SwayveMetadataQuery(
        title: 'Bloom (Extended Intro Mix)',
        artists: ['Sultan + Shepard'],
        album: 'Bloom',
        year: 2019,
        duration: Duration(minutes: 7, seconds: 3),
        trackNumber: 1,
        discNumber: 1,
        isrc: 'US1234567890',
        sourceUrl: Uri.parse('https://nebula.example/watch?v=abc'),
        providerId: 'yt123',
      );
      expect(
        SwayveMetadataQuery.fromJson(roundTripJson(query.toJson())),
        query,
      );
    });

    test('SwayveMetadataQuery, minimally populated', () {
      const minimal = SwayveMetadataQuery(title: 'Bloom');
      final parsed =
          SwayveMetadataQuery.fromJson(roundTripJson(minimal.toJson()));
      expect(parsed, minimal);
      expect(parsed.artists, isEmpty);
    });

    test('SwayveMetadataCandidate, fully populated', () {
      final candidate = SwayveMetadataCandidate(
        providerItemId: 'yt123',
        title: 'Bloom (Extended Intro Mix)',
        artists: const ['Sultan + Shepard'],
        album: 'Bloom',
        year: 2019,
        duration: const Duration(minutes: 7, seconds: 3),
        artwork: Uri.parse('https://example.com/art.jpg'),
        isrc: 'US1234567890',
        sourceUrl: Uri.parse('https://nebula.example/watch?v=abc'),
        extra: const {'videoId': 'abc'},
      );
      final parsed = SwayveMetadataCandidate.fromJson(
        roundTripJson(candidate.toJson()),
      );
      expect(parsed, candidate);
      expect(parsed.hashCode, candidate.hashCode);
    });

    test('SwayveMetadataCandidate, minimally populated', () {
      const minimal = SwayveMetadataCandidate(title: 'Bloom');
      final parsed = SwayveMetadataCandidate.fromJson(
        roundTripJson(minimal.toJson()),
      );
      expect(parsed, minimal);
      expect(parsed.artists, isEmpty);
      expect(parsed.extra, isEmpty);
    });

    test('SwayveRadio, fully populated', () {
      final radio = SwayveRadio(
        id: const SwayveMediaId('app.swayve.plugins.example', 'radio/1'),
        title: 'Radio based on A Song / With Punctuation',
        seed: trackId,
        artwork: artwork,
        extra: const {'continuation': 'abc'},
      );
      final parsed = SwayveRadio.fromJson(roundTripJson(radio.toJson()));
      expect(parsed, radio);
      expect(parsed.hashCode, radio.hashCode);
    });

    test('SwayveRadio, minimally populated', () {
      const minimal = SwayveRadio(
        id: SwayveMediaId('app.swayve.plugins.example', 'radio/1'),
      );
      final parsed = SwayveRadio.fromJson(roundTripJson(minimal.toJson()));
      expect(parsed, minimal);
      expect(parsed.title, isNull);
      expect(parsed.seed, isNull);
      expect(parsed.extra, isEmpty);
    });

    test('SwayveVisual, fully populated', () {
      final visual = SwayveVisual(
        uri: Uri.parse('https://example.com/video.m3u8'),
        kind: SwayveVisualKind.video,
        aspectRatio: 16 / 9,
        loops: false,
        source: 'Example Visuals',
        duration: const Duration(minutes: 3, seconds: 44),
      );
      final parsed = SwayveVisual.fromJson(roundTripJson(visual.toJson()));
      expect(parsed, visual);
      expect(parsed.hashCode, visual.hashCode);
      expect(parsed.aspectRatio, 16 / 9);
    });

    test('SwayveVisual, minimally populated, loops by default', () {
      final minimal = SwayveVisual(
        uri: Uri.parse('https://example.com/cover.mp4'),
        kind: SwayveVisualKind.motionArtwork,
      );
      final parsed = SwayveVisual.fromJson(roundTripJson(minimal.toJson()));
      expect(parsed, minimal);
      expect(parsed.loops, isTrue);
      expect(parsed.aspectRatio, isNull);
      expect(parsed.duration, isNull);
    });

    test('SwayveAlbum', () {
      expect(
        SwayveAlbum.fromJson(roundTripJson(fullAlbum.toJson())),
        fullAlbum,
      );
    });

    test('SwayveArtist', () {
      expect(
        SwayveArtist.fromJson(roundTripJson(fullArtist.toJson())),
        fullArtist,
      );
    });

    test('SwayveArtist with only an id and a name', () {
      expect(
        SwayveArtist.fromJson(roundTripJson(thinArtist.toJson())),
        thinArtist,
      );
    });

    test('SwayveArtistSection, one per kind', () {
      // Every kind, so that a member added to the enum without a wire name
      // fails here rather than at whichever provider first emits it.
      for (final kind in SwayveArtistSectionKind.values) {
        final section = SwayveArtistSection(
          kind: kind,
          title: 'Shelf ${kind.wireName}',
          tracks: [fullTrack],
          albums: [fullAlbum],
          artists: const [thinArtist],
          playlists: [fullPlaylist],
          more: const SwayveMediaId('app.swayve.plugins.example', 'more'),
        );
        expect(
          SwayveArtistSection.fromJson(roundTripJson(section.toJson())),
          section,
          reason: kind.name,
        );
      }
    });

    test('an empty section keeps its kind and drops its empty lists', () {
      const section = SwayveArtistSection(kind: SwayveArtistSectionKind.videos);
      expect(section.isEmpty, isTrue);
      expect(section.toJson(), {'kind': 'videos'});
      expect(
        SwayveArtistSection.fromJson(roundTripJson(section.toJson())),
        section,
      );
    });

    test('SwayvePlaylist', () {
      expect(
        SwayvePlaylist.fromJson(roundTripJson(fullPlaylist.toJson())),
        fullPlaylist,
      );
    });

    test('SwayveSearchQuery', () {
      const query = SwayveSearchQuery(
        text: 'boards of canada',
        kinds: {SwayveSearchKind.track, SwayveSearchKind.album},
        limit: 5,
        cursor: 'abc',
      );
      expect(
        SwayveSearchQuery.fromJson(roundTripJson(query.toJson())),
        query,
      );
    });

    test('SwayveSearchResult', () {
      final result = SwayveSearchResult(
        tracks: [fullTrack],
        albums: [fullAlbum],
        artists: [fullArtist],
        playlists: [fullPlaylist],
        cursor: 'next',
        partial: true,
      );
      final parsed =
          SwayveSearchResult.fromJson(roundTripJson(result.toJson()));
      expect(parsed, result);
      expect(parsed.partial, isTrue);
      expect(parsed.hasMore, isTrue);
    });

    test('SwayveSearchResult, empty', () {
      final parsed = SwayveSearchResult.fromJson(
        roundTripJson(SwayveSearchResult.empty.toJson()),
      );
      expect(parsed, SwayveSearchResult.empty);
      expect(parsed.isEmpty, isTrue);
      expect(parsed.hasMore, isFalse);
    });

    test('SwayveBrowseRequest', () {
      const request = SwayveBrowseRequest(
        limit: 25,
        cursor: 'page-2',
        sort: SwayveSortOrder.alphabetical,
      );
      expect(
        SwayveBrowseRequest.fromJson(roundTripJson(request.toJson())),
        request,
      );
      expect(
        SwayveBrowseRequest.fromJson(
          roundTripJson(SwayveBrowseRequest.first.toJson()),
        ),
        SwayveBrowseRequest.first,
      );
    });

    test('SwayvePage', () {
      final page = SwayvePage<SwayveTrack>(
        items: [fullTrack],
        cursor: 'more',
      );
      final parsed = SwayvePage.fromJson<SwayveTrack>(
        roundTripJson(page.toJson((track) => track.toJson())),
        SwayveTrack.fromJson,
      );
      expect(parsed, page);
      expect(parsed.hasMore, isTrue);
      expect(parsed.items.single, fullTrack);
    });

    test('SwayveLyrics', () {
      const lyrics = SwayveLyrics(
        plain: 'line one\nline two',
        synced: [
          SwayveLyricLine(at: Duration.zero, text: 'line one'),
          SwayveLyricLine(at: Duration(seconds: 12), text: 'line two'),
        ],
        source: 'Example Lyrics',
        explicitContent: true,
      );
      final parsed = SwayveLyrics.fromJson(roundTripJson(lyrics.toJson()));
      expect(parsed, lyrics);
      expect(parsed.isSynced, isTrue);
      expect(parsed.words, isNull);
      expect(parsed.hasWordTiming, isFalse);
    });

    test('SwayveLyrics carrying word timing', () {
      const lyrics = SwayveLyrics(
        plain: 'line one\nline two',
        synced: [
          SwayveLyricLine(at: Duration.zero, text: 'line one'),
          SwayveLyricLine(at: Duration(seconds: 12), text: 'line two'),
        ],
        words: [
          [
            SwayveLyricWord(
              at: Duration.zero,
              until: Duration(milliseconds: 400),
              text: 'line',
            ),
            SwayveLyricWord(
              at: Duration(milliseconds: 400),
              until: Duration(milliseconds: 900),
              text: 'one',
            ),
          ],
          [
            SwayveLyricWord(
              at: Duration(seconds: 12),
              until: Duration(milliseconds: 12400),
              text: 'line',
            ),
            SwayveLyricWord(
              at: Duration(milliseconds: 12400),
              until: Duration(milliseconds: 12900),
              text: 'two',
            ),
          ],
        ],
        source: 'Example Lyrics',
      );
      final parsed = SwayveLyrics.fromJson(roundTripJson(lyrics.toJson()));
      expect(parsed, lyrics);
      expect(parsed.hashCode, lyrics.hashCode);
      expect(parsed.hasWordTiming, isTrue);
      // The grouping is the point of the nested list: two lines with two words
      // each, not one flat run of four.
      expect(parsed.words, hasLength(2));
      expect(parsed.words!.first.map((word) => word.text), ['line', 'one']);
    });

    test('SwayveLyrics with only word timing keeps synced null', () {
      const lyrics = SwayveLyrics(
        words: [
          [
            SwayveLyricWord(
              at: Duration.zero,
              until: Duration(milliseconds: 500),
              text: 'alone',
            ),
          ],
        ],
      );
      final parsed = SwayveLyrics.fromJson(roundTripJson(lyrics.toJson()));
      expect(parsed, lyrics);
      expect(parsed.synced, isNull);
      expect(parsed.isSynced, isFalse);
      expect(parsed.hasWordTiming, isTrue);
    });

    test('SwayveLyricWord', () {
      const word = SwayveLyricWord(
        at: Duration(milliseconds: 1234),
        until: Duration(milliseconds: 1600),
        text: 'a',
      );
      expect(
        SwayveLyricWord.fromJson(roundTripJson(word.toJson())),
        word,
      );
    });

    test('SwayveLyricLine', () {
      const line = SwayveLyricLine(
        at: Duration(milliseconds: 1234),
        text: 'a line',
      );
      expect(
        SwayveLyricLine.fromJson(roundTripJson(line.toJson())),
        line,
      );
    });

    test('SwayveScrobble', () {
      final scrobble = SwayveScrobble(
        id: trackId,
        title: 'A Song',
        artist: 'Ärtist One, Guest',
        album: 'The Album',
        duration: const Duration(seconds: 222),
        playedAt: DateTime.utc(2026, 8, 15, 12, 30, 5),
      );
      expect(
        SwayveScrobble.fromJson(roundTripJson(scrobble.toJson())),
        scrobble,
      );
    });

    test('SwayveScrobble normalizes playedAt to UTC', () {
      final local = DateTime(2026, 8, 15, 12, 30, 5);
      final scrobble = SwayveScrobble(
        id: trackId,
        title: 'A Song',
        artist: 'Someone',
        playedAt: local,
      );
      final parsed = SwayveScrobble.fromJson(roundTripJson(scrobble.toJson()));
      expect(parsed.playedAt.isUtc, isTrue);
      expect(parsed.playedAt.isAtSameMomentAs(local), isTrue);
      expect(parsed, scrobble);
    });

    test('SwayveAuthState', () {
      final state = SwayveAuthState(
        status: SwayveAuthStatus.signedIn,
        accountLabel: 'someone@example.com',
        expiresAt: DateTime.utc(2026, 9, 1),
        message: null,
      );
      expect(
        SwayveAuthState.fromJson(roundTripJson(state.toJson())),
        state,
      );
      expect(
        SwayveAuthState.fromJson(
          roundTripJson(SwayveAuthState.signedOut.toJson()),
        ),
        SwayveAuthState.signedOut,
      );
    });

    test('SwayveWebEmbed', () {
      final embed = SwayveWebEmbed(
        kind: SwayveWebEmbedKind.inAppWebView,
        uri: Uri.parse('https://example.com/embed?id=1'),
        controls: const {
          SwayveEmbedControl.play,
          SwayveEmbedControl.pause,
          SwayveEmbedControl.positionUpdates,
        },
        userAgent: 'Swayve/1.0',
      );
      expect(SwayveWebEmbed.fromJson(roundTripJson(embed.toJson())), embed);
    });

    test('SwayvePlaybackHints', () {
      const hints = SwayvePlaybackHints(
        preferAudioOnly: false,
        maxBitrateKbps: 128,
        allowWebEmbed: false,
      );
      expect(
        SwayvePlaybackHints.fromJson(roundTripJson(hints.toJson())),
        hints,
      );
      expect(
        SwayvePlaybackHints.fromJson(
          roundTripJson(SwayvePlaybackHints.defaults.toJson()),
        ),
        SwayvePlaybackHints.defaults,
      );
    });

    test('SwayveHostInfo', () {
      final info = SwayveHostInfo(
        swayveVersion: Version.parse('1.1.0'),
        swayvePluginApi: kSwayvePluginApiVersion,
        platform: SwayvePlatform.ios,
        supportedEmbeds: const {SwayveWebEmbedKind.inAppWebView},
        locale: 'en-GB',
        region: 'GB',
      );
      expect(SwayveHostInfo.fromJson(roundTripJson(info.toJson())), info);
    });

    test('SwayvePluginIdentity', () {
      final identity = SwayvePluginIdentity(
        id: 'app.swayve.plugins.nebula_music',
        name: 'Nebula Music',
        version: Version.parse('0.1.0'),
        swayvePluginApi: 1,
        capabilities: const {
          SwayveCapability.search,
          SwayveCapability.catalog,
          SwayveCapability.streaming,
          SwayveCapability.artwork,
          SwayveCapability.playlistRead,
        },
        permissions: const {
          SwayvePermission.network,
          SwayvePermission.webview,
          SwayvePermission.externalAuth,
          SwayvePermission.localPluginStorage,
        },
      );
      final parsed =
          SwayvePluginIdentity.fromJson(roundTripJson(identity.toJson()));
      expect(parsed, identity);
      expect(parsed.has(SwayveCapability.playlistRead), isTrue);
      expect(parsed.needs(SwayvePermission.clipboard), isFalse);
      expect(
        identity.toJson()['capabilities'],
        containsAll(<String>['playlist_read', 'search']),
      );
      expect(
        identity.toJson()['permissions'],
        containsAll(<String>['external_auth', 'local_plugin_storage']),
      );
    });
  });

  group('playback sources round-trip by kind', () {
    final directUrl = SwayvePlayableSource.directUrl(
      Uri.parse('https://cdn.example.com/a.m4a'),
      headers: const {'authorization': 'Bearer redacted'},
      expiresIn: const Duration(minutes: 30),
      mimeType: 'audio/mp4',
    );
    final hls = SwayvePlayableSource.hls(
      Uri.parse('https://cdn.example.com/a.m3u8'),
    );
    final dash = SwayvePlayableSource.dash(
      Uri.parse('https://cdn.example.com/a.mpd'),
    );
    final localFile = SwayvePlayableSource.localFile(
      Uri.parse('file:///music/a.m4a'),
    );
    final webEmbed = SwayvePlayableSource.webEmbed(
      SwayveWebEmbed(
        kind: SwayveWebEmbedKind.iframe,
        uri: Uri.parse('https://example.com/embed'),
        controls: const {SwayveEmbedControl.play},
      ),
    );

    for (final source in [directUrl, hls, dash, localFile, webEmbed]) {
      test(source.kind.wireName, () {
        expect(
          SwayvePlayableSource.fromJson(roundTripJson(source.toJson())),
          source,
        );
      });
    }

    test('a URL source carries its headers and expiry', () {
      expect(directUrl.kind, SwayvePlayableKind.directUrl);
      expect(directUrl.headers['authorization'], 'Bearer redacted');
      expect(directUrl.expiresIn, const Duration(minutes: 30));
      expect(directUrl.embed, isNull);
      expect(directUrl.isWebEmbed, isFalse);
    });

    test('a web embed carries no uri of its own', () {
      expect(webEmbed.uri, isNull);
      expect(webEmbed.isWebEmbed, isTrue);
      expect(webEmbed.embed, isNotNull);
    });

    test('a local file defaults to on-device availability', () {
      expect(localFile.availability.onDevice, isTrue);
      expect(localFile.availability.streamable, isFalse);
    });
  });

  group('copyWith', () {
    test('replaces only what it is given', () {
      final changed = fullTrack.copyWith(title: 'Renamed');
      expect(changed.title, 'Renamed');
      expect(changed.id, fullTrack.id);
      expect(changed.artists, fullTrack.artists);
      expect(fullTrack.copyWith(), fullTrack);
    });

    test('works across the other models', () {
      expect(fullAlbum.copyWith(year: 1999).year, 1999);
      expect(fullArtist.copyWith(name: 'Other').name, 'Other');
      expect(fullPlaylist.copyWith(trackCount: 1).trackCount, 1);
      expect(fullTrack.copyWith(canSeedRadio: false).canSeedRadio, isFalse);
      expect(artwork.copyWith(width: 1).width, 1);
      expect(albumRef.copyWith(title: 'X').title, 'X');
      expect(
        const SwayveBrowseRequest().next('c').cursor,
        'c',
      );
    });
  });

  test('artistsLabel joins credited artists in order', () {
    expect(fullTrack.artistsLabel, 'Ärtist One, Guest');
    expect(fullAlbum.artistsLabel, 'Ärtist One');
  });

  test('copyWith reaches the radio, visuals and word-timing models', () {
    const radio = SwayveRadio(
      id: SwayveMediaId('app.swayve.plugins.example', 'radio/1'),
    );
    expect(radio.copyWith(title: 'Named').title, 'Named');
    expect(radio.copyWith(seed: trackId).seed, trackId);
    expect(radio.copyWith(), radio);

    final visual = SwayveVisual(
      uri: Uri.parse('https://example.com/cover.mp4'),
      kind: SwayveVisualKind.motionArtwork,
    );
    expect(visual.copyWith(loops: false).loops, isFalse);
    expect(
      visual.copyWith(kind: SwayveVisualKind.video).kind,
      SwayveVisualKind.video,
    );
    expect(visual.copyWith(), visual);

    const word = SwayveLyricWord(
      at: Duration.zero,
      until: Duration(milliseconds: 100),
      text: 'a',
    );
    expect(word.copyWith(text: 'b').text, 'b');
    expect(word.copyWith(), word);

    const lyrics = SwayveLyrics(plain: 'a lyric');
    expect(lyrics.hasWordTiming, isFalse);
    expect(
      lyrics.copyWith(
        words: const [
          [SwayveLyricWord(at: Duration.zero, until: Duration.zero, text: 'a')],
        ],
      ).hasWordTiming,
      isTrue,
    );
    expect(lyrics.copyWith(), lyrics);
  });

  test('a track that cannot seed a radio differs from one that can', () {
    expect(fullTrack.canSeedRadio, isTrue);
    expect(fullTrack.copyWith(canSeedRadio: false), isNot(fullTrack));
  });

  test('value equality distinguishes deep differences in extra', () {
    final other = fullTrack.copyWith(extra: const {'sourceId': 'different'});
    expect(other, isNot(fullTrack));
  });

  test('SwayvePage.map converts items and keeps the cursor', () {
    final page = SwayvePage<SwayveTrack>(items: [fullTrack], cursor: 'c');
    final titles = page.map((track) => track.title);
    expect(titles.items, ['A Song / With Punctuation']);
    expect(titles.cursor, 'c');
  });
}
