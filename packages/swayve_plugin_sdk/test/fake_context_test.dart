import 'dart:async';

import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:swayve_plugin_sdk/testing.dart';
import 'package:test/test.dart';

/// A plugin that declares `search` and `network` and behaves itself.
final class _WellBehavedPlugin implements SwayvePlugin {
  _WellBehavedPlugin();

  SwayvePluginContext? context;
  bool disposed = false;

  @override
  SwayvePluginIdentity get identity => SwayvePluginIdentity(
        id: 'app.swayve.plugins.example',
        name: 'Example',
        version: Version.parse('0.1.0'),
        capabilities: const {SwayveCapability.search},
        permissions: const {SwayvePermission.network},
      );

  @override
  Future<void> initialize(SwayvePluginContext context) async {
    this.context = context;
    context.log.info('initializing');
    context.registerSearchProvider(_EchoSearchProvider(context.http));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// A plugin that reaches for storage it never declared.
final class _OverReachingPlugin implements SwayvePlugin {
  @override
  SwayvePluginIdentity get identity => SwayvePluginIdentity(
        id: 'app.swayve.plugins.greedy',
        name: 'Greedy',
        version: Version.parse('0.1.0'),
        capabilities: const {SwayveCapability.search},
      );

  @override
  Future<void> initialize(SwayvePluginContext context) async {
    await context.storage.write('anything', 'at all');
  }

  @override
  Future<void> dispose() async {}
}

final class _EchoArtistActivityProvider
    implements SwayveArtistActivityProvider {
  @override
  Future<SwayvePage<SwayveTrack>> likedTracks(
    SwayveMediaId artistId,
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  }) async =>
      const SwayvePage(items: []);

  @override
  Future<SwayvePage<SwayveTrack>> repostedTracks(
    SwayveMediaId artistId,
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  }) async =>
      const SwayvePage(items: []);
}

final class _EchoLibraryProvider implements SwayveLibraryProvider {
  @override
  Future<SwayvePage<SwayveTrack>> likedTracks(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  }) async =>
      const SwayvePage(items: []);
}

final class _EchoLibraryPushProvider implements SwayveLibraryPushProvider {
  @override
  SwayveUploadHashAlgorithm? get dedupAlgorithm => SwayveUploadHashAlgorithm.md5;

  @override
  Future<Set<String>> knownUploadHashes({
    SwayveCancellationToken? cancel,
  }) async =>
      const {};

  @override
  Future<SwayveUploadResult> uploadTrack(
    SwayveUploadItem item, {
    SwayveCancellationToken? cancel,
  }) async =>
      const SwayveUploadResult(outcome: SwayveUploadOutcome.uploaded);
}

final class _EchoSearchProvider implements SwayveSearchProvider {
  _EchoSearchProvider(this._http);

  final SwayveHttpClient _http;

  @override
  Future<SwayveSearchResult> search(
    SwayveSearchQuery query, {
    SwayveCancellationToken? cancel,
  }) async {
    final response = await _http.get(
      Uri.https('example.test', '/search', {'q': query.text}),
      headers: const {'accept': 'application/json'},
      cancel: cancel,
    );
    final body = response.bodyAsJson;
    if (body is! Map<String, Object?>) {
      throw const SwayvePluginMalformedResponseException(
        'Search response was not an object.',
      );
    }
    final titles = body['titles'];
    if (titles is! List) {
      return SwayveSearchResult.empty;
    }
    return SwayveSearchResult(
      tracks: [
        for (final title in titles)
          SwayveTrack(
            id: SwayveMediaId('app.swayve.plugins.example', '$title'),
            title: '$title',
            availability: SwayveAvailability.streamOnly,
          ),
      ],
    );
  }
}

void main() {
  group('permission enforcement', () {
    test('a declared facility is available', () {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      expect(context.http, isA<SwayveHttpClient>());
      expect(context.hasPermission(SwayvePermission.network), isTrue);
    });

    test('an undeclared facility throws synchronously', () {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      expect(
        () => context.storage,
        throwsA(
          isA<SwayvePermissionDeniedException>().having(
            (error) => error.permission,
            'permission',
            SwayvePermission.localPluginStorage,
          ),
        ),
      );
      expect(
        () => context.credentials,
        throwsA(
          isA<SwayvePermissionDeniedException>().having(
            (error) => error.permission,
            'permission',
            SwayvePermission.externalAuth,
          ),
        ),
      );
      expect(
        () => context.webView,
        throwsA(
          isA<SwayvePermissionDeniedException>().having(
            (error) => error.permission,
            'permission',
            SwayvePermission.webview,
          ),
        ),
      );
      expect(
        () => context.sessionCapture,
        throwsA(
          isA<SwayvePermissionDeniedException>().having(
            (error) => error.permission,
            'permission',
            SwayvePermission.webview,
          ),
        ),
      );
    });

    test('a context with no permissions grants no guarded facility', () {
      final context = FakeSwayvePluginContext();
      for (final access in <void Function()>[
        () => context.http,
        () => context.storage,
        () => context.credentials,
        () => context.webView,
        () => context.sessionCapture,
      ]) {
        expect(access, throwsA(isA<SwayvePermissionDeniedException>()));
      }
    });

    test(
        'session capture requires both webview and external_auth; only '
        'webview is not enough', () {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.webview},
      );
      expect(
        () => context.sessionCapture,
        throwsA(
          isA<SwayvePermissionDeniedException>().having(
            (error) => error.permission,
            'permission',
            SwayvePermission.externalAuth,
          ),
        ),
      );
    });

    test('unguarded facilities are always available', () {
      final context = FakeSwayvePluginContext();
      expect(context.host, FakeSwayvePluginContext.defaultHostInfo);
      expect(context.log, isA<SwayvePluginLogger>());
      expect(context.settings, isA<SwayveSettingsView>());
    });

    test('every guarded facility is reachable when everything is granted', () {
      final context = FakeSwayvePluginContext(
        permissions: SwayvePermission.values.toSet(),
      );
      expect(context.http, isNotNull);
      expect(context.storage, isNotNull);
      expect(context.credentials, isNotNull);
      expect(context.webView, isNotNull);
      expect(context.sessionCapture, isNotNull);
    });

    test('the denial names the permission the plugin should have declared', () {
      final context = FakeSwayvePluginContext();
      try {
        context.storage;
        fail('expected a permission denial');
      } on SwayvePermissionDeniedException catch (error) {
        expect(error.message, contains('local_plugin_storage'));
        expect(error.code, 'permission_denied');
        expect(error.toString(), contains('local_plugin_storage'));
      }
    });

    test('an over-reaching plugin fails during initialize', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      await expectLater(
        _OverReachingPlugin().initialize(context),
        throwsA(isA<SwayvePermissionDeniedException>()),
      );
      expect(context.fakeStorage.entries, isEmpty);
    });
  });

  group('provider registration', () {
    test('registrations are recorded and mapped back to capabilities',
        () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      final plugin = _WellBehavedPlugin();
      await plugin.initialize(context);

      expect(context.searchProviders, hasLength(1));
      expect(context.catalogProviders, isEmpty);
      expect(context.registeredCapabilities, plugin.identity.capabilities);
      expect(context.fakeLogger.messages, contains('initializing'));

      await plugin.dispose();
      expect(plugin.disposed, isTrue);
      await context.close();
    });

    test('an artist-activity provider is recorded and mapped back', () {
      final context = FakeSwayvePluginContext();
      final provider = _EchoArtistActivityProvider();

      context.registerArtistActivityProvider(provider);

      expect(context.artistActivityProviders, [provider]);
      expect(
        context.registeredCapabilities,
        contains(SwayveCapability.artistActivity),
      );
    });

    test('a library provider is recorded and mapped back', () {
      final context = FakeSwayvePluginContext();
      final provider = _EchoLibraryProvider();

      context.registerLibraryProvider(provider);

      expect(context.libraryProviders, [provider]);
      expect(
        context.registeredCapabilities,
        contains(SwayveCapability.personalLibrary),
      );
    });

    test('a library-push provider is recorded and mapped back', () {
      final context = FakeSwayvePluginContext();
      final provider = _EchoLibraryPushProvider();

      context.registerLibraryPushProvider(provider);

      expect(context.libraryPushProviders, [provider]);
      expect(
        context.registeredCapabilities,
        contains(SwayveCapability.personalLibraryPush),
      );
    });

    test('a registered provider runs against the scripted network', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      final plugin = _WellBehavedPlugin();
      await plugin.initialize(context);
      context.fakeHttp.enqueueJson({
        'titles': ['One', 'Two'],
      });

      final provider = context.searchProviders.single;
      final result = await provider.search(
        const SwayveSearchQuery(text: 'boards of canada'),
      );

      expect(result.tracks.map((track) => track.title), ['One', 'Two']);
      expect(context.fakeHttp.requests, hasLength(1));
      final request = context.fakeHttp.lastRequest!;
      expect(request.method, 'GET');
      expect(request.url.queryParameters['q'], 'boards of canada');
      expect(request.headers['accept'], 'application/json');
      await context.close();
    });

    test('a provider surfaces a malformed upstream response', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      final plugin = _WellBehavedPlugin();
      await plugin.initialize(context);
      context.fakeHttp.enqueueText('<html>502</html>', statusCode: 502);

      await expectLater(
        context.searchProviders.single.search(
          const SwayveSearchQuery(text: 'x'),
        ),
        throwsA(isA<SwayvePluginMalformedResponseException>()),
      );
      await context.close();
    });

    test('a provider surfaces a transport failure', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      final plugin = _WellBehavedPlugin();
      await plugin.initialize(context);
      context.fakeHttp.enqueueError();

      await expectLater(
        context.searchProviders.single.search(
          const SwayveSearchQuery(text: 'x'),
        ),
        throwsA(isA<SwayvePluginUnavailableException>()),
      );
      await context.close();
    });
  });

  group('FakeSwayveHttpClient', () {
    test('serves queued responses in order and records every request',
        () async {
      final client = FakeSwayveHttpClient()
        ..enqueueJson({'n': 1})
        ..enqueueText('second');

      final first = await client.get(Uri.parse('https://a.test/1'));
      final second = await client.post(
        Uri.parse('https://a.test/2'),
        body: 'payload',
      );

      expect(first.bodyAsJson, {'n': 1});
      expect(first.statusCode, 200);
      expect(first.isSuccess, isTrue);
      expect(second.bodyAsString, 'second');
      expect(client.requests.map((request) => request.method), ['GET', 'POST']);
      expect(client.requests.last.body, 'payload');
      expect(client.pending, 0);
    });

    test('a non-2xx status is a response, not a throw', () async {
      final client = FakeSwayveHttpClient()
        ..enqueueJson({'error': 'nope'}, statusCode: 429);
      final response = await client.get(Uri.parse('https://a.test/x'));
      expect(response.statusCode, 429);
      expect(response.isSuccess, isFalse);
    });

    test('an unscripted call is a test error, not a silent success', () {
      final client = FakeSwayveHttpClient();
      expect(
        () => client.get(Uri.parse('https://a.test/x')),
        throwsStateError,
      );
    });

    test('a queued error is thrown', () async {
      final client = FakeSwayveHttpClient()
        ..enqueueError(
          const SwayvePluginRateLimitedException(
            'slow down',
            retryAfter: Duration(seconds: 30),
          ),
        );
      await expectLater(
        client.get(Uri.parse('https://a.test/x')),
        throwsA(
          isA<SwayvePluginRateLimitedException>().having(
            (error) => error.retryAfter,
            'retryAfter',
            const Duration(seconds: 30),
          ),
        ),
      );
    });

    test('reset forgets requests and queued results', () async {
      final client = FakeSwayveHttpClient()..enqueueText('x');
      await client.get(Uri.parse('https://a.test/x'));
      expect(client.requests, hasLength(1));
      client.reset();
      expect(client.requests, isEmpty);
      expect(client.pending, 0);
    });
  });

  group('InMemorySwayvePluginStorage', () {
    test('reads back what it wrote and forgets what it deleted', () async {
      final storage = InMemorySwayvePluginStorage();
      expect(await storage.read('missing'), isNull);
      await storage.write('cursor', 'abc');
      expect(await storage.read('cursor'), 'abc');
      expect(storage.entries, {'cursor': 'abc'});
      await storage.delete('cursor');
      expect(await storage.read('cursor'), isNull);
      await storage.write('a', '1');
      await storage.clear();
      expect(storage.entries, isEmpty);
    });

    test('rejects keys the host would reject', () {
      final storage = InMemorySwayvePluginStorage();
      for (final key in ['', 'has space', 'has/slash', 'a' * 129, 'ünicode']) {
        expect(
          () => storage.read(key),
          throwsA(isA<ArgumentError>()),
          reason: key,
        );
      }
    });
  });

  group('InMemorySwayveCredentialStore', () {
    test('keeps secrets apart from plugin storage', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {
          SwayvePermission.externalAuth,
          SwayvePermission.localPluginStorage,
        },
      );
      await context.credentials.writeSecret('refresh_token', 'super-secret');
      expect(
        await context.credentials.readSecret('refresh_token'),
        'super-secret',
      );
      expect(context.fakeCredentials.secretKeys, {'refresh_token'});
      expect(context.fakeStorage.entries, isEmpty);
      await context.credentials.deleteSecret('refresh_token');
      expect(context.fakeCredentials.hasSecret('refresh_token'), isFalse);
      await context.close();
    });
  });

  group('RecordingSwayvePluginLogger', () {
    test('records level, message and attached error', () {
      final logger = RecordingSwayvePluginLogger()
        ..debug('d')
        ..info('i')
        ..warn('w', error: StateError('bad'))
        ..error('e', error: 'boom', stackTrace: StackTrace.empty);

      expect(logger.messages, ['d', 'i', 'w', 'e']);
      expect(logger.at(SwayveLogLevel.warn).single.message, 'w');
      expect(logger.at(SwayveLogLevel.error).single.error, 'boom');
      expect(logger.contains('i'), isTrue);
      expect(logger.contains('token=abc'), isFalse);
      logger.clear();
      expect(logger.entries, isEmpty);
    });
  });

  group('FakeSwayveSettingsView', () {
    test('reads declared values and ignores type mismatches', () {
      final settings = FakeSwayveSettingsView({'region': 'GB', 'hd': true});
      expect(settings.value<String>('region'), 'GB');
      expect(settings.value<bool>('hd'), isTrue);
      expect(settings.value<int>('region'), isNull);
      expect(settings.value<String>('missing'), isNull);
    });

    test('notifies on change', () async {
      final settings = FakeSwayveSettingsView({'region': 'GB'});
      final changes = <void>[];
      final subscription = settings.changes.listen(changes.add);
      settings.set('region', 'US');
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(1));
      expect(settings.value<String>('region'), 'US');
      await subscription.cancel();
      await settings.close();
    });
  });

  group('FakeSwayveWebViewController', () {
    test('replays navigation through the plugin predicate', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.webview},
      );
      context.fakeWebView.enqueueNavigation([
        Uri.parse('https://provider.test/login'),
        Uri.parse('https://provider.test/consent'),
        Uri.parse('swayve://callback?code=123'),
      ]);

      final result = await context.webView.presentForResult(
        Uri.parse('https://provider.test/login'),
        isComplete: (url) => url.queryParameters.containsKey('code'),
      );

      expect(result?.queryParameters['code'], '123');
      expect(context.fakeWebView.presentations, hasLength(1));
      await context.close();
    });

    test('a dismissal resolves as null', () async {
      final controller = FakeSwayveWebViewController()..enqueueDismissal();
      final result = await controller.presentForResult(
        Uri.parse('https://provider.test/login'),
        isComplete: (_) => true,
      );
      expect(result, isNull);
    });

    test('a timeout throws', () async {
      final controller = FakeSwayveWebViewController()..enqueueTimeout();
      await expectLater(
        controller.presentForResult(
          Uri.parse('https://provider.test/login'),
          isComplete: (_) => true,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<SwayvePluginTimeoutException>()),
      );
    });
  });

  group('FakeSwayveSessionCaptureController', () {
    test(
        'a successful capture writes the scripted secrets into '
        'fakeCredentials', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {
          SwayvePermission.webview,
          SwayvePermission.externalAuth,
        },
      );
      context.fakeSessionCapture.enqueueNavigation(
        [
          Uri.parse('https://music.example.test/login'),
          Uri.parse('https://music.example.test/home'),
        ],
        capturedSecrets: const {
          'session_cookie': 'cookie-value',
          'page_id': 'page-id-value',
        },
      );

      final result = await context.sessionCapture.presentForSessionCapture(
        Uri.parse('https://music.example.test/login'),
        isComplete: (url) => url.path == '/home',
      );

      expect(result.outcome, SwayveSessionCaptureOutcome.succeeded);
      expect(result.isSuccess, isTrue);
      expect(result.completionUrl?.path, '/home');
      expect(
        await context.credentials.readSecret('session_cookie'),
        'cookie-value',
      );
      expect(await context.credentials.readSecret('page_id'), 'page-id-value');
      expect(context.fakeSessionCapture.presentations, hasLength(1));
      await context.close();
    });

    test('a dismissal resolves without writing any secret', () async {
      final context = FakeSwayvePluginContext(
        permissions: const {
          SwayvePermission.webview,
          SwayvePermission.externalAuth,
        },
      );
      context.fakeSessionCapture.enqueueDismissal();

      final result = await context.sessionCapture.presentForSessionCapture(
        Uri.parse('https://music.example.test/login'),
        isComplete: (_) => true,
      );

      expect(result.outcome, SwayveSessionCaptureOutcome.dismissed);
      expect(result.completionUrl, isNull);
      expect(context.fakeCredentials.secretKeys, isEmpty);
    });

    test('a timeout throws', () async {
      final controller =
          FakeSwayveSessionCaptureController(InMemorySwayveCredentialStore())
            ..enqueueTimeout();
      await expectLater(
        controller.presentForSessionCapture(
          Uri.parse('https://music.example.test/login'),
          isComplete: (_) => true,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<SwayvePluginTimeoutException>()),
      );
    });
  });

  test('the default fake host describes a plausible Swayve', () {
    const host = FakeSwayvePluginContext.defaultHostInfo;
    expect(host.swayvePluginApi, kSwayvePluginApiVersion);
    expect(host.supportsEmbed(SwayveWebEmbedKind.inAppWebView), isTrue);
    expect(host.supportsEmbed(SwayveWebEmbedKind.iframe), isFalse);
    expect(host.locale, 'en-GB');
  });
}
