import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('SwayveCapability', () {
    test('every value round-trips through its wire name', () {
      for (final capability in SwayveCapability.values) {
        expect(
          SwayveCapability.fromWire(capability.wireName),
          capability,
          reason: capability.name,
        );
      }
    });

    test('wire names are the manifest vocabulary, exactly', () {
      expect(
        SwayveCapability.values.map((value) => value.wireName).toList(),
        [
          'search',
          'catalog',
          'streaming',
          'metadata',
          'lyrics',
          'scrobbling',
          'authentication',
          'webview',
          'artwork',
          'playlist_read',
          'artist_activity',
        ],
      );
    });

    test('playlistRead is snake_case on the wire, camelCase in Dart', () {
      expect(SwayveCapability.playlistRead.wireName, 'playlist_read');
      expect(
        SwayveCapability.fromWire('playlist_read'),
        SwayveCapability.playlistRead,
      );
      expect(SwayveCapability.fromWire('playlistRead'), isNull);
    });

    test('artistActivity is snake_case on the wire, camelCase in Dart', () {
      expect(SwayveCapability.artistActivity.wireName, 'artist_activity');
      expect(
        SwayveCapability.fromWire('artist_activity'),
        SwayveCapability.artistActivity,
      );
      expect(SwayveCapability.fromWire('artistActivity'), isNull);
    });

    test('unknown names return null rather than throwing', () {
      expect(SwayveCapability.fromWire('teleportation'), isNull);
      expect(SwayveCapability.fromWire(''), isNull);
      expect(SwayveCapability.fromWire('SEARCH'), isNull);
    });

    test('wire names are unique', () {
      final names = SwayveCapability.values.map((v) => v.wireName).toSet();
      expect(names.length, SwayveCapability.values.length);
    });
  });

  group('SwayvePermission', () {
    test('every value round-trips through its wire name', () {
      for (final permission in SwayvePermission.values) {
        expect(
          SwayvePermission.fromWire(permission.wireName),
          permission,
          reason: permission.name,
        );
      }
    });

    test('wire names are the manifest vocabulary, exactly', () {
      expect(
        SwayvePermission.values.map((value) => value.wireName).toList(),
        [
          'network',
          'webview',
          'external_auth',
          'local_plugin_storage',
          'clipboard',
        ],
      );
    });

    test('external_auth and local_plugin_storage map correctly', () {
      expect(SwayvePermission.externalAuth.wireName, 'external_auth');
      expect(
        SwayvePermission.fromWire('external_auth'),
        SwayvePermission.externalAuth,
      );
      expect(
        SwayvePermission.localPluginStorage.wireName,
        'local_plugin_storage',
      );
      expect(
        SwayvePermission.fromWire('local_plugin_storage'),
        SwayvePermission.localPluginStorage,
      );
      expect(SwayvePermission.fromWire('externalAuth'), isNull);
      expect(SwayvePermission.fromWire('localPluginStorage'), isNull);
    });

    test('unknown names return null rather than throwing', () {
      expect(SwayvePermission.fromWire('filesystem'), isNull);
    });
  });

  group('the remaining wire vocabularies', () {
    test('SwayvePlatform round-trips', () {
      for (final value in SwayvePlatform.values) {
        expect(SwayvePlatform.fromWire(value.wireName), value);
      }
      expect(SwayvePlatform.fromWire('symbian'), isNull);
    });

    test('SwayveArtworkSize round-trips', () {
      for (final value in SwayveArtworkSize.values) {
        expect(SwayveArtworkSize.fromWire(value.wireName), value);
      }
    });

    test('SwayveSearchKind round-trips', () {
      for (final value in SwayveSearchKind.values) {
        expect(SwayveSearchKind.fromWire(value.wireName), value);
      }
    });

    test('SwayveSortOrder round-trips', () {
      for (final value in SwayveSortOrder.values) {
        expect(SwayveSortOrder.fromWire(value.wireName), value);
      }
    });

    test('SwayvePlayableKind round-trips and is snake_case', () {
      for (final value in SwayvePlayableKind.values) {
        expect(SwayvePlayableKind.fromWire(value.wireName), value);
      }
      expect(SwayvePlayableKind.directUrl.wireName, 'direct_url');
      expect(SwayvePlayableKind.hlsUrl.wireName, 'hls_url');
      expect(SwayvePlayableKind.dashUrl.wireName, 'dash_url');
      expect(SwayvePlayableKind.localFile.wireName, 'local_file');
      expect(SwayvePlayableKind.webEmbed.wireName, 'web_embed');
    });

    test('SwayveWebEmbedKind round-trips and is snake_case', () {
      for (final value in SwayveWebEmbedKind.values) {
        expect(SwayveWebEmbedKind.fromWire(value.wireName), value);
      }
      expect(SwayveWebEmbedKind.inAppWebView.wireName, 'in_app_web_view');
    });

    test('SwayveEmbedControl round-trips and is snake_case', () {
      for (final value in SwayveEmbedControl.values) {
        expect(SwayveEmbedControl.fromWire(value.wireName), value);
      }
      expect(SwayveEmbedControl.positionUpdates.wireName, 'position_updates');
    });

    test('SwayveAuthStatus round-trips and is snake_case', () {
      for (final value in SwayveAuthStatus.values) {
        expect(SwayveAuthStatus.fromWire(value.wireName), value);
      }
      expect(SwayveAuthStatus.signedOut.wireName, 'signed_out');
      expect(SwayveAuthStatus.signedIn.wireName, 'signed_in');
    });
  });

  test('the API level constants', () {
    expect(kSwayvePluginApiVersion, 1);
    expect(kSwayveManifestSchemaVersion, 2);
    expect(kSwayveMediaIdScheme, 'swayve');
  });

  test('the default timeouts are the documented budgets', () {
    expect(SwayveTimeouts.request, const Duration(seconds: 10));
    expect(SwayveTimeouts.operation, const Duration(seconds: 20));
    expect(SwayveTimeouts.initialize, const Duration(seconds: 8));
    expect(SwayveTimeouts.dispose, const Duration(seconds: 3));
  });
}
