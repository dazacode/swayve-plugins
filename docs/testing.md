# Testing

A plugin is testable without a Swayve build, without a network, and without
Flutter. If your plugin needs any of those to be tested, something has been
wired wrong.

```bash
cd my_plugin        # wherever your plugin lives; no plugin lives in this repo
dart test
```

Examples below name plugin directories by the path they had while this
repository still contained plugins directly. It does not any more — adjust the
path to your own plugin, or clone [`swayve-plugin-example`](https://github.com/dazacode/swayve-plugin-example)
alongside this one to run a command as written.

Plugin tests use `package:test` and run under `dart test`, not the Flutter test
runner. If a plugin genuinely needs Flutter, say why in its README — but note
that the SDK has no Flutter dependency, so a plugin implementing only provider
interfaces never does.

There is no `--directory` flag on `dart test`. Each plugin resolves its own
`pubspec.yaml`, so you run the suite from inside the plugin directory; that is
exactly what CI does.

---

## The test harness

```dart
import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:swayve_plugin_sdk/testing.dart';
import 'package:test/test.dart';
```

`testing.dart` is a separate export, deliberately not reachable from the main
library: nothing in a shipping plugin should ever import a fake.

| Fake | Stands in for | Notable behaviour |
|---|---|---|
| `FakeSwayvePluginContext` | `SwayvePluginContext` | **Enforces the declared permission set** through the same `SwayvePermissionEnforcement` mixin the host uses. Also records every `register*` call. |
| `FakeSwayveHttpClient` | `SwayveHttpClient` | Queue canned responses, record outgoing requests, or induce an error or a hang. |
| `FakeSwayveSettingsView` | `SwayveSettingsView` | Map-backed, with `set` to simulate the user editing a setting. |
| `FakeSwayveWebViewController` | `SwayveWebViewController` | Scripts navigation, dismissal or timeout through the plugin's own `isComplete` predicate. |
| `InMemorySwayvePluginStorage` | `SwayvePluginStorage` | Real semantics, and it enforces the host's key pattern. |
| `InMemorySwayveCredentialStore` | `SwayveCredentialStore` | Same, for secrets. Exposes `secretKeys`/`hasSecret` but not values. |
| `RecordingSwayvePluginLogger` | `SwayvePluginLogger` | Keeps every entry, so you can assert that a token was *not* logged. |
| `SwayveCancellationTokenSource` | producer of `SwayveCancellationToken` | Lets a test cancel mid-call and assert the provider stopped. |

### `FakeSwayvePluginContext`

Construct it with the permissions your `plugin.json` actually declares — not
with all of them. **The default grants nothing**, which is the right default.

```dart
final context = FakeSwayvePluginContext(
  permissions: {SwayvePermission.network},
);

context.http;      // fine — network is declared
context.storage;   // throws SwayvePermissionDeniedException
                   //   (permission: SwayvePermission.localPluginStorage)
```

Each facility is also reachable directly, unguarded, for assertions — that is
what the `fake*` fields are for. A test inspects `fakeStorage`; the plugin must
go through `storage`.

| Member | Use |
|---|---|
| `fakeHttp` | Queue responses, assert on `requests` |
| `fakeStorage` | Inspect `entries` without the permission |
| `fakeCredentials` | Assert on `secretKeys` / `hasSecret` |
| `fakeLogger` | Assert on `messages`, `entries`, `at(level)`, `contains(needle)` |
| `fakeSettings` | Call `set(id, value)` to simulate a user edit |
| `fakeWebView` | Script navigation and assert on `presentations` |
| `grantedPermissions` | The set the context was built with |
| `searchProviders`, `catalogProviders`, `streamProviders`, `metadataProviders`, `lyricsProviders`, `scrobbleProviders`, `artworkProviders`, `playlistProviders`, `artistActivityProviders`, `authProviders`, `libraryProviders` | What the plugin registered |
| `registeredCapabilities` | Those lists collapsed to a `Set<SwayveCapability>` |
| `close()` | **Await it in teardown.** Cancels hung requests and closes the settings stream. |

Any facility can be replaced through the constructor when a test needs to script
it. Its default host is `Swayve 1.1.0` on `android`, API level 1, with
`{SwayveWebEmbedKind.inAppWebView}` supported — override `host:` to test other
platforms or an embed-less host.

That includes reproducing a Linux/WSL host with no locale configured, without
needing an actual Linux machine to do it — copy the default, switch the
platform, and blank the locale:

```dart
final context = FakeSwayvePluginContext(
  host: FakeSwayvePluginContext.defaultHostInfo.copyWith(
    platform: SwayvePlatform.linux,
    locale: '',
  ),
  permissions: {SwayvePermission.network},
);
```

`SwayveHostInfo.region` is nullable and already exercises the "unknown"
path when omitted; `locale` is not nullable, so an empty string is the
realistic failure shape to test against, not `null`. See
[development.md](development.md#platform-notes) for why this specific case is
worth a test rather than a hypothetical.

`registeredCapabilities` is the assertion that closes the loop between the
manifest and the code:

```dart
test('registers exactly the capabilities the manifest declares', () async {
  final context = FakeSwayvePluginContext();
  addTearDown(context.close);

  await createMyPlugin().initialize(context);

  expect(
    context.registeredCapabilities,
    {SwayveCapability.search, SwayveCapability.catalog},
  );
});
```

### `FakeSwayveHttpClient` — responses, errors and hangs

Responses are consumed in order regardless of URL, which keeps a test honest
about how many calls its plugin makes.

```dart
final http = FakeSwayveHttpClient();

// Canned results, consumed in order.
http.enqueueJson({'items': <Object?>[], 'next': null});
http.enqueueText('not json at all');
http.enqueueResponse(
  const SwayveHttpResponse(statusCode: 429, headers: {'retry-after': '30'}),
);

// Make the next call throw. Defaults to SwayvePluginUnavailableException.
http.enqueueError();
http.enqueueError(const SwayvePluginTimeoutException('too slow'));

// Make the next call never complete.
http.enqueueHang();

// Assert on what was actually sent.
expect(http.requests, hasLength(1));
expect(http.requests.single.method, 'POST');
expect(http.requests.single.url.host, 'music.youtube.com');
expect(http.lastRequest!.headers, isNot(contains('authorization')));
expect(http.pending, 0);          // every queued result was consumed

http.cancelHangs();               // fail any outstanding hung future
http.reset();                     // forget requests and queue
```

A call with nothing queued throws a `StateError` naming the request, rather than
returning an empty response — an unexpected request is a test failure, not a
default.

The hang case is the one people skip and the one that catches real bugs. A
provider that awaits forever is indistinguishable from a broken plugin, and the
host will move it to `degraded`. `cancelHangs()` (which `context.close()` calls
for you) completes any outstanding hung future with a transport failure, so a
forgotten deadline fails the test instead of hanging the runner.

### Cancellation

`enqueueHang()` respects a cancellation token: cancelling completes the pending
future with `SwayvePluginCancelledException`.

```dart
test('search stops when the query is cancelled', () async {
  final context = FakeSwayvePluginContext(
    permissions: {SwayvePermission.network},
  );
  addTearDown(context.close);
  context.fakeHttp.enqueueHang();

  final source = SwayveCancellationTokenSource();
  final pending = MySearchProvider(context.http).search(
    const SwayveSearchQuery(text: 'radiohead'),
    cancel: source.token,
  );
  source.cancel();

  await expectLater(pending, throwsA(isA<SwayvePluginCancelledException>()));
});
```

Search runs on every keystroke, so cancellation is the common path there, not an
edge case.

### Web view flows

`FakeSwayveWebViewController` replays URLs through the plugin's own `isComplete`
predicate, so a test exercises the real redirect-matching logic rather than a
stubbed answer.

```dart
final context = FakeSwayvePluginContext(
  permissions: {SwayvePermission.webview, SwayvePermission.externalAuth},
);
addTearDown(context.close);

context.fakeWebView.enqueueNavigation([
  Uri.parse('https://example.com/authorize'),
  Uri.parse('https://example.com/callback?code=abc123'),
]);

// …run the flow…
expect(context.fakeWebView.presentations, hasLength(1));
```

`enqueueDismissal()` makes the presentation resolve `null` — the user backed
out. `enqueueTimeout()` makes it throw `SwayvePluginTimeoutException`. A
presentation with nothing scripted throws `StateError`.

### Asserting the error contract

Every provider method must complete, throw a `SwayvePluginException`, or honour
cancellation within `SwayveTimeouts.operation` (20s). Test the throws
explicitly, because the host branches on the type. Every subtype takes a
required positional message:

```dart
test('rate limiting surfaces as SwayvePluginRateLimitedException', () async {
  final context = FakeSwayvePluginContext(
    permissions: {SwayvePermission.network},
  );
  addTearDown(context.close);
  context.fakeHttp.enqueueResponse(
    const SwayveHttpResponse(statusCode: 429, headers: {'retry-after': '30'}),
  );

  await expectLater(
    MySearchProvider(context.http).search(const SwayveSearchQuery(text: 'x')),
    throwsA(
      isA<SwayvePluginRateLimitedException>()
          .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))
          .having((e) => e.code, 'code', 'plugin_rate_limited'),
    ),
  );
});
```

Every `SwayvePluginException` carries a stable `code` string
(`plugin_unavailable`, `plugin_timeout`, `plugin_cancelled`,
`plugin_auth_required`, `plugin_rate_limited`, `plugin_malformed_response`,
`plugin_unsupported`, `permission_denied`, `incompatible_api`) and an optional
`cause`. Asserting on `code` is more durable than asserting on `message`.

A raw `FormatException` or `TypeError` escaping a provider is a bug. The SDK's
own `fromJson` methods already throw
`SwayvePluginMalformedResponseException` rather than a `TypeError`, and
`SwayveHttpResponse.bodyAsJson` does the same for a body that is not JSON — so
in most cases you get the right exception by letting it propagate.

### Asserting that secrets stay out of logs

```dart
test('the authorization header is never logged', () async {
  final context = FakeSwayvePluginContext(
    permissions: {SwayvePermission.network, SwayvePermission.externalAuth},
  );
  addTearDown(context.close);

  // …run the auth flow with a known fake token…

  expect(context.fakeLogger.contains(fakeToken), isFalse);
  expect(context.fakeLogger.at(SwayveLogLevel.error), isEmpty);
});
```

---

## What to test

| Test | Why it earns its place |
|---|---|
| Happy-path decode for each provider method | Catches upstream shape drift, the most common real-world breakage |
| Pagination: first page, middle page, last page (`cursor == null`, so `hasMore` is false) | Off-by-one cursor bugs are invisible until a user scrolls |
| Empty result vs. error | `null`/empty means "not found"; a throw means "could not find out". The host renders them differently |
| Malformed JSON | Must become `SwayvePluginMalformedResponseException`, not a crash |
| HTTP 401 / 403 | Usually `SwayvePluginAuthRequiredException` — but only if your plugin *has* a sign-in flow. `plugins/youtube_music` maps 403 to unavailable precisely because it declares no `authentication` capability, and offering a sign-in button that leads nowhere is worse than a plain failure |
| HTTP 429 | `SwayvePluginRateLimitedException`, with `retryAfter` when the header is present |
| Hang | Must not hang forever |
| Cancellation | Must stop |
| Permission over-reach | Must throw against the fake, using the manifest's exact permission set |
| `registeredCapabilities` vs the manifest | Catches a capability declared and never registered, and the reverse |
| Every outbound URL against `network.hosts` | Read the allow-list from `plugin.json` itself, not from a constant in the plugin |
| Availability mapping | `streamable`, `downloadable`, `onDevice` set independently and correctly |
| Empty or malformed `host.locale` / `.region` | Not hypothetical — a real bug on Linux/WSL, whose default locale is frequently unset. See [development.md](development.md#platform-notes) and the `host:` override example above |

The last two are worth copying from `plugins/youtube_music`, whose
`network_allowlist_test.dart` and `manifest_agreement_test.dart` read the real
manifest at test time rather than trusting the plugin's own copy of its facts.

---

## Acceptance checklist

These are the nine properties the whole system is judged on. They span this
repository and the host, so several are host-side tests that cannot pass until
the client work in [host-integration.md](host-integration.md) exists — those are
marked. Each one exists to prove a specific principle, not to raise coverage.

### A · Swayve Core builds and runs with zero plugins

Build and launch the client with no plugin registered, no plugin directory, and
this repository deleted from disk. Search, browse, play, download.

**Proves** that nothing here is load-bearing for the app. If A ever fails, the
plugin system has become a dependency rather than an extension, and every other
guarantee in this document is worth less.

### B · Declared permissions are enforced, undeclared access throws

Construct a plugin's providers against a `FakeSwayvePluginContext` carrying
exactly the manifest's permission set, and access a facility the manifest does
not declare.

**Proves** that the permission list a user reads is the permission set that
actually applies — enforcement, not documentation. `plugins/example` runs the
whole lifecycle plus every provider method against a context with **nothing**
granted (`test/permission_guard_test.dart`), which is the strongest form of this
test. Runs today.

### C · An invalid manifest is rejected with a specific diagnostic

Feed the validator a fixture per rule and assert the diagnostic **code**, not
the message text. Assert too that packaging refuses. The fixtures under
`test/fixtures/plugins/` — `misnamed_directory`, `no_licenses`,
`offline_catalogue` — exist for exactly this.

**Proves** that failures are legible and stable enough to automate against, and
that a broken manifest can never reach a loader. Runs today.

### D · A plugin that throws or hangs does not break Swayve

Register a provider that throws on every call, and another that never completes.
Search, browse and play.

**Proves** principle 7 — every host→plugin call is timeout-bounded and
error-isolated. The failing plugin goes to `degraded` and shows
*"&lt;Plugin name&gt; — Temporarily unavailable"*; everything else keeps working.
The plugin-side half runs today (`plugins/youtube_music`'s
`failure_modes_test.dart` covers every exception mapping, the hang and
cancellation on every provider); the host-side half is **pending host work**.

### E · Packaging is deterministic

Package the same plugin twice, from a clean and a dirty working directory, on
two platforms. Compare bytes. The tools suite is run on Windows as well as Linux
in CI for precisely this reason — a path-separator or line-ending bug would hide
on Linux alone.

**Proves** that a published artefact is reproducible by anyone with the source,
which is what makes the `.sha256` sidecar and the signature meaningful. Pair it
with the extraction-safety fixtures — traversal entries, symlinks, zip bombs,
oversized entries — which must all be rejected
(`test/extraction_safety_test.dart`). Runs today.

### F · No plugin-specific branching in the search screen

Grep the client for plugin ids. Then add a second plugin implementing
`SwayveSearchProvider` and confirm its results appear with **no client change**.

**Proves** principle 2 — the client resolves behaviour through provider
interfaces only. The client's existing search-result grouping is already
provider-agnostic (it buckets by library id, not by provider identity), so this
is achievable — but it requires the search path to become async, which it is not
today. **Pending host work**; see
[host-integration.md](host-integration.md#search).

### G · `runtime: bundled` with platform `ios` is rejected

Validate a fixture declaring both.

**Proves** that the iOS restriction is mechanical rather than cultural. Assert
the error code `bundled_runtime_not_allowed_on_ios`, assert packaging refuses,
and assert there is no flag that changes the outcome. Runs today.

### H · Streamable, downloadable and on-device are independent

Construct tracks for each of the eight combinations and assert nothing derives
one from another anywhere in the pipeline.

**Proves** principle 6. The combinations that catch real bugs are
*downloadable but not streamable* (a source that only permits offline) and
*on-device but no longer streamable* (the upstream removed it) — both of which
break code that treats the three as a ladder. `plugins/example` is the degenerate
case worth keeping in mind: every track reports
`SwayveAvailability.none`, because knowing about a track grants no right to play
it. Plugin side runs today; the host mapping onto the client's 3-way
availability enum is **pending host work**.

### I · One plugin cannot read another plugin's storage

Write a value from plugin A, then attempt to read it from plugin B by every
means the API offers.

**Proves** the isolation model. The intended result is that there is no
expressible way to try: `SwayvePluginStorage` takes no plugin id and has no key
enumeration, so isolation follows from the shape of the API rather than from a
check that could be forgotten. The test asserts that this stays true. Plugin
side runs today; host-backed namespacing is **pending host work**.

---

## Running everything

```bash
dart format . && dart analyze
dart run tools/validate_plugin.dart --all --strict --plugins-root ../plugins
dart test                                        # tools, from the repo root
(cd packages/swayve_plugin_sdk && dart test)
(cd ../swayve-plugin-example/example && dart test)
(cd ../my_plugin && dart test)
```

CI runs the same commands: `validate` covers formatting, `dart analyze
--fatal-infos`, manifest validation with `--strict`, and every `plugin.json`
against the published JSON Schema; `test` discovers every package with a
`test/` directory and runs its suite in its own directory.

---

## See also

- [capabilities.md](capabilities.md) — the contracts each provider method must honour
- [permissions.md](permissions.md) — what test B is enforcing
- [packaging.md](packaging.md) — the determinism and extraction rules test E covers
- [development.md](development.md) — where testing sits in the loop
