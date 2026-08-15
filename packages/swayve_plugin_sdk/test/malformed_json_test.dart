import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

/// `fromJson` is parsing data that came from a network response the plugin
/// does not control, so it must never let a `TypeError` escape.
final Matcher throwsMalformed =
    throwsA(isA<SwayvePluginMalformedResponseException>());

void main() {
  group('missing required fields are malformed', () {
    test('SwayveTrack without an id', () {
      expect(
        () => SwayveTrack.fromJson({'title': 'x'}),
        throwsMalformed,
      );
    });

    test('SwayveTrack without a title', () {
      expect(
        () => SwayveTrack.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
        }),
        throwsMalformed,
      );
    });

    test('SwayveMediaId without a value', () {
      expect(
        () => SwayveMediaId.fromJson({'pluginId': 'a.b.c'}),
        throwsMalformed,
      );
    });

    test('SwayveImageRef without a uri', () {
      expect(() => SwayveImageRef.fromJson({'width': 10}), throwsMalformed);
    });

    test('SwayveLyricLine without a timestamp', () {
      expect(
        () => SwayveLyricLine.fromJson({'text': 'x'}),
        throwsMalformed,
      );
    });

    test('SwayveScrobble without playedAt', () {
      expect(
        () => SwayveScrobble.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
          'title': 'x',
          'artist': 'y',
        }),
        throwsMalformed,
      );
    });

    test('an empty object for every model', () {
      expect(() => SwayveTrack.fromJson(const {}), throwsMalformed);
      expect(() => SwayveAlbum.fromJson(const {}), throwsMalformed);
      expect(() => SwayveArtist.fromJson(const {}), throwsMalformed);
      expect(() => SwayvePlaylist.fromJson(const {}), throwsMalformed);
      expect(() => SwayveArtistRef.fromJson(const {}), throwsMalformed);
      expect(() => SwayveAlbumRef.fromJson(const {}), throwsMalformed);
      expect(() => SwayveMediaId.fromJson(const {}), throwsMalformed);
      expect(() => SwayveImageRef.fromJson(const {}), throwsMalformed);
      expect(() => SwayveSearchQuery.fromJson(const {}), throwsMalformed);
      expect(() => SwayveHostInfo.fromJson(const {}), throwsMalformed);
      expect(() => SwayvePluginIdentity.fromJson(const {}), throwsMalformed);
      expect(() => SwayveAuthState.fromJson(const {}), throwsMalformed);
      expect(() => SwayveWebEmbed.fromJson(const {}), throwsMalformed);
      expect(() => SwayvePlayableSource.fromJson(const {}), throwsMalformed);
    });
  });

  group('wrongly typed fields are malformed', () {
    test('a number where a string belongs', () {
      expect(
        () => SwayveArtistRef.fromJson({'name': 42}),
        throwsMalformed,
      );
    });

    test('a string where an object belongs', () {
      expect(
        () => SwayveTrack.fromJson({'id': 'swayve://a.b.c/x', 'title': 't'}),
        throwsMalformed,
      );
    });

    test('a string where a list belongs', () {
      expect(
        () => SwayveArtist.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
          'name': 'n',
          'genres': 'rock',
        }),
        throwsMalformed,
      );
    });

    test('a non-string inside a list of strings', () {
      expect(
        () => SwayveArtist.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
          'name': 'n',
          'genres': ['rock', 7],
        }),
        throwsMalformed,
      );
    });

    test('a string where a bool belongs', () {
      expect(
        () => SwayveAvailability.fromJson({'streamable': 'yes'}),
        throwsMalformed,
      );
    });

    test('a fractional number where an integer belongs', () {
      expect(
        () => SwayveImageRef.fromJson({
          'uri': 'https://x.test/a.png',
          'width': 12.5,
        }),
        throwsMalformed,
      );
    });

    test('a non-object where a nested object belongs', () {
      expect(
        () => SwayveTrack.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
          'title': 't',
          'album': 7,
        }),
        throwsMalformed,
      );
    });

    test('a list of non-objects where a list of objects belongs', () {
      expect(
        () => SwayveTrack.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
          'title': 't',
          'artists': ['just a name'],
        }),
        throwsMalformed,
      );
    });

    test('an object with non-string keys', () {
      expect(
        () => SwayveTrack.fromJson({
          'id': <Object?, Object?>{7: 'a.b.c'},
          'title': 't',
        }),
        throwsMalformed,
      );
    });

    test('a bad timestamp', () {
      expect(
        () => SwayveScrobble.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
          'title': 'x',
          'artist': 'y',
          'playedAt': 'the day before yesterday',
        }),
        throwsMalformed,
      );
    });

    test('a bad version', () {
      expect(
        () => SwayveHostInfo.fromJson({
          'swayveVersion': 'v1',
          'swayvePluginApi': 1,
          'platform': 'android',
        }),
        throwsMalformed,
      );
    });
  });

  group('unknown enum members are malformed', () {
    test('an unknown capability', () {
      expect(
        () => SwayvePluginIdentity.fromJson({
          'id': 'a.b.c',
          'name': 'n',
          'version': '1.0.0',
          'capabilities': ['search', 'teleportation'],
          'permissions': <String>[],
        }),
        throwsMalformed,
      );
    });

    test('a camelCase capability that should be snake_case', () {
      expect(
        () => SwayvePluginIdentity.fromJson({
          'id': 'a.b.c',
          'name': 'n',
          'version': '1.0.0',
          'capabilities': ['playlistRead'],
          'permissions': <String>[],
        }),
        throwsMalformed,
      );
    });

    test('an unknown permission', () {
      expect(
        () => SwayvePluginIdentity.fromJson({
          'id': 'a.b.c',
          'name': 'n',
          'version': '1.0.0',
          'capabilities': ['search'],
          'permissions': ['filesystem'],
        }),
        throwsMalformed,
      );
    });

    test('an unknown platform', () {
      expect(
        () => SwayveHostInfo.fromJson({
          'swayveVersion': '1.0.0',
          'swayvePluginApi': 1,
          'platform': 'symbian',
        }),
        throwsMalformed,
      );
    });
  });

  group('inconsistent playable sources are malformed', () {
    test('a web embed with no embed', () {
      expect(
        () => SwayvePlayableSource.fromJson({'kind': 'web_embed'}),
        throwsMalformed,
      );
    });

    test('a url kind with no uri', () {
      expect(
        () => SwayvePlayableSource.fromJson({'kind': 'direct_url'}),
        throwsMalformed,
      );
    });

    test('an unknown kind', () {
      expect(
        () => SwayvePlayableSource.fromJson({'kind': 'carrier_pigeon'}),
        throwsMalformed,
      );
    });

    test('non-string header values', () {
      expect(
        () => SwayvePlayableSource.fromJson({
          'kind': 'direct_url',
          'uri': 'https://x.test/a.m4a',
          'headers': {'x': 7},
        }),
        throwsMalformed,
      );
    });
  });

  group('the failure carries a useful message', () {
    test('it names the model and the field', () {
      try {
        SwayveTrack.fromJson({
          'id': {'pluginId': 'a.b.c', 'value': 'x'},
        });
        fail('expected a malformed-response failure');
      } on SwayvePluginMalformedResponseException catch (error) {
        expect(error.message, contains('SwayveTrack.title'));
        expect(error.code, 'plugin_malformed_response');
        expect(error.toString(), contains('SwayveTrack.title'));
      }
    });

    test('it is a SwayvePluginException, so a host can switch on it', () {
      const error = SwayvePluginMalformedResponseException('nope');
      expect(error, isA<SwayvePluginException>());
      expect(error, isA<Exception>());
    });
  });

  test('an HTTP body that is not JSON is malformed', () {
    final response = SwayveHttpResponse.text('<html>error</html>');
    expect(() => response.bodyAsJson, throwsMalformed);
  });

  test('an empty HTTP body decodes as null rather than throwing', () {
    const response = SwayveHttpResponse(statusCode: 204);
    expect(response.bodyAsJson, isNull);
  });
}
