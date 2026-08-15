# swayve_plugin_sdk

The contract between the [Swayve](https://github.com/dazacode/swayve-plugins)
music client and a Swayve plugin.

Pure Dart. No Flutter dependency, no `dart:io`, no `dart:ui`, and exactly one
runtime dependency (`meta`). A plugin built against this SDK is unit-testable
with `dart test` and compiles into a host that uses any UI toolkit.

- **API level:** 1
- **Manifest schema version:** 1
- **Dart SDK:** `^3.6.0`
- **License:** Apache-2.0

## Install

The SDK is consumed as a git dependency, not from pub.dev:

```yaml
dependencies:
  swayve_plugin_sdk:
    git:
      url: https://github.com/dazacode/swayve-plugins.git
      path: packages/swayve_plugin_sdk

dev_dependencies:
  test: ^1.25.0
```

## What a plugin looks like

A plugin is one class implementing `SwayvePlugin`, plus one implementation per
capability it declares.

```dart
import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';

final class ExamplePlugin implements SwayvePlugin {
  late final SwayvePluginContext _context;

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
    _context = context;
    context.registerSearchProvider(ExampleSearchProvider(context.http));
  }

  @override
  Future<void> dispose() async {}
}

/// The single symbol the host looks for. Its name must match the manifest's
/// `entrypoint`.
SwayvePlugin example() => ExamplePlugin();
```

Everything the plugin is allowed to touch arrives through the context, and
everything it supplies leaves through a provider. There is no other seam.

## The seven rules the shape follows

1. **Swayve works with zero plugins.** Nothing here is required for the client
   to build or run.
2. **The host has no hardcoded knowledge of any plugin.** It resolves behaviour
   through the provider interfaces and nothing else — there is no place for
   `if (plugin.id == 'youtube_music')`.
3. **Plugins talk to their own services from the user's device.** Swayve hosts
   no per-plugin proxy.
4. **Permissions, not encryption, are the security model.** A facility a plugin
   did not declare is not reachable.
5. **Plugins supply data; the host renders UI.** No widgets cross this boundary,
   which is also why the SDK has no Flutter dependency.
6. **Streamable, downloadable and on-device are three independent facts.** See
   `SwayveAvailability`; never derive one from another.
7. **A broken plugin must never break Swayve.** Every call is timeout-bounded,
   cancellable and error-isolated.

## Capabilities and their providers

Each capability in a `plugin.json` maps to exactly one interface. Declare it,
implement it, register it in `initialize`.

| Capability      | Wire name       | Interface                 |
| --------------- | --------------- | ------------------------- |
| search          | `search`        | `SwayveSearchProvider`    |
| catalog         | `catalog`       | `SwayveCatalogProvider`   |
| streaming       | `streaming`     | `SwayveStreamProvider`    |
| metadata        | `metadata`      | `SwayveMetadataProvider`  |
| lyrics          | `lyrics`        | `SwayveLyricsProvider`    |
| scrobbling      | `scrobbling`    | `SwayveScrobbleProvider`  |
| authentication  | `authentication`| `SwayveAuthProvider`      |
| webview         | `webview`       | (permission only)         |
| artwork         | `artwork`       | `SwayveArtworkProvider`   |
| playlistRead    | `playlist_read` | `SwayvePlaylistProvider`  |

## Permissions and the facilities they guard

| Permission           | Wire name              | Facility                     |
| -------------------- | ---------------------- | ---------------------------- |
| `network`            | `network`              | `context.http`               |
| `webview`            | `webview`              | `context.webView`            |
| `externalAuth`       | `external_auth`        | `context.credentials`        |
| `localPluginStorage` | `local_plugin_storage` | `context.storage`            |
| `clipboard`          | `clipboard`            | host clipboard write         |

`context.host`, `context.log` and `context.settings` are always available.
Reading a guarded getter without its permission throws
`SwayvePermissionDeniedException` **synchronously**, so the stack trace names
the line that over-reached.

Not grantable in v1, at all: the user's music files, Swayve account
credentials, another plugin's storage, arbitrary filesystem paths, device
secrets, background execution.

## Identifiers

`SwayveMediaId` is `swayve://<pluginId>/<percent-encoded value>`. The `value`
is the provider's own identifier and is opaque to the host — it is never
parsed, matched or reasoned about. The round trip is exact for any value,
including ones containing `/`, spaces, `?` and non-ASCII characters.

```dart
const id = SwayveMediaId('app.swayve.plugins.example', 'a/b c?d');
SwayveMediaId.parse(id.uri) == id; // always true
```

## Serialization

Hand-written `toJson` / `fromJson` on every model. No code generation, no
`build_runner`, matching the Swayve client, which uses none either.

Every `fromJson` is defensive: it is parsing data that ultimately came from a
network response, so malformed input throws
`SwayvePluginMalformedResponseException` naming the model and field, never a
raw `TypeError`.

## Errors, timeouts and cancellation

`SwayvePluginException` is `sealed`, so a host can switch over it
exhaustively:

| Exception                            | Meaning                                |
| ------------------------------------ | -------------------------------------- |
| `SwayvePluginUnavailableException`    | transient: outage, offline, unreachable |
| `SwayvePluginTimeoutException`        | a deadline was exceeded                |
| `SwayvePluginCancelledException`      | the host asked for the work to stop    |
| `SwayvePluginAuthRequiredException`   | the user must sign in first            |
| `SwayvePluginRateLimitedException`    | upstream is throttling, with a hint    |
| `SwayvePluginMalformedResponseException` | a response could not be interpreted |
| `SwayvePluginUnsupportedException`    | the plugin does not do this            |
| `SwayvePermissionDeniedException`     | an undeclared facility was touched     |
| `SwayveIncompatibleApiException`      | the plugin needs a newer host          |

Every provider method must complete, throw one of those, or honour
cancellation within `SwayveTimeouts.operation` (20s). The host applies its own
hard deadline regardless and treats a breach as
`SwayvePluginUnavailableException`.

```dart
Future<SwayveSearchResult> search(
  SwayveSearchQuery query, {
  SwayveCancellationToken? cancel,
}) async {
  cancel?.throwIfCancelled();
  final response = await _http.get(url, cancel: cancel);
  cancel?.throwIfCancelled();
  return _parse(response);
}
```

## Testing without a host

`package:swayve_plugin_sdk/testing.dart` ships fakes for every facility. The
important one is `FakeSwayvePluginContext`: it enforces the permission set you
declare, so a plugin that reaches too far fails in your test suite rather than
on a user's phone.

```dart
import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:swayve_plugin_sdk/testing.dart';
import 'package:test/test.dart';

void main() {
  test('search maps the upstream payload', () async {
    final context = FakeSwayvePluginContext(
      permissions: const {SwayvePermission.network}, // exactly your manifest
    );
    final plugin = ExamplePlugin();
    await plugin.initialize(context);

    context.fakeHttp.enqueueJson({'titles': ['One']});
    final result = await context.searchProviders.single.search(
      const SwayveSearchQuery(text: 'query'),
    );

    expect(result.tracks.single.title, 'One');
    expect(context.fakeHttp.lastRequest!.url.host, 'example.test');
    await context.close();
  });
}
```

Also included: `FakeSwayveHttpClient` (queue responses, record requests,
simulate a throw or a hang), `InMemorySwayvePluginStorage`,
`InMemorySwayveCredentialStore`, `RecordingSwayvePluginLogger`,
`FakeSwayveSettingsView`, `FakeSwayveWebViewController` and
`SwayveCancellationTokenSource`.

Nothing in a shipping plugin should import this library — it is deliberately
not exported from the main one.

## Development

```bash
dart pub get
dart format .
dart analyze   # must report zero issues
dart test
```

## License

Apache-2.0. Copyright Swayve.
