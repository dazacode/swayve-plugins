# Development

The loop you will spend your time in, the layout that makes it comfortable, and
the dependency decision that keeps both repositories independent.

> **Read this first.** The Swayve client does not have a plugin system yet — no
> loader, no registry, no extension points. Steps 1, 2 and 5 of the loop below
> work today against the tooling and the SDK's test harness. Steps 3 and 4
> describe the intended experience once the host work in
> [host-integration.md](host-integration.md) lands, and are marked accordingly.
> Everything in this document that is not yet real is labelled; nothing is
> described as working when it is not.

---

## Prerequisites

- Dart SDK **3.6.0 or newer** (developed against 3.13.0). No Flutter needed for
  the SDK, the tools, or plugin tests.
- Git.

```bash
dart --version
```

On Linux, install the Dart SDK however your distro prefers — the
[archive tarball](https://dart.dev/get-dart), or `sudo apt install dart` on
Debian/Ubuntu once Dart's own apt repository is added, per
[dart.dev/get-dart](https://dart.dev/get-dart). No `PATH` quirks or Flutter
dependency to work around: this repository and `Daza-Swayve-plugins` are pure
Dart packages, not Flutter apps, so nothing here needs the Flutter SDK, a
Linux desktop toolchain, or GTK/GStreamer — that list is `swayve-client`'s, for
building the host app itself, not for writing a plugin against it.

### Platform notes

Every command in this document is already what a Linux (or macOS) developer
would run — this repository has no PowerShell anywhere, on any platform, since
`dart`/`git` behave identically wherever they run. There is nothing
Linux-specific to translate.

One real gotcha, discovered developing `youtube_music` under WSL and worth
knowing before it costs you an afternoon: **`SwayveHostInfo.locale` is
documented as a BCP-47 tag (`en-GB`) but is not guaranteed to actually be
one.** A Linux dev machine — WSL especially, which ships with no system locale
configured by default — can have a host pass through an empty string rather
than a well-formed tag. `youtube_music`'s `language` getter
(`youtube_music/lib/src/innertube_client.dart` in `Daza-Swayve-plugins`) is
the fix to copy: trim it, fall back to `'en'` on empty, and take only the
primary subtag before `-`/`_` rather than trusting the whole string is
present and well-shaped. Any provider that builds a request from `host.locale`
or `host.region` should do the same defensive parsing rather than assume the
doc comment's example format always holds — see
[testing.md](testing.md#what-to-test) for how to reproduce this in a test
without needing a Linux machine at all.

---

## Local layout

Clone this repository *beside* the Swayve client:

```
C:\dev\personalmusicsync\
├── swayve-client\        # the Flutter app (pub package `music_sync`)
└── swayve-plugins\       # this repository
```

Siblings, not nested. The two are separate git repositories with separate
histories, separate issues and separate releases; if you do place this checkout
inside the client's directory tree, add `/swayve-plugins/` to the client's
`.gitignore` so it does not show up as untracked there.

The layout is a **convenience, not a dependency**. Nothing in either repository
resolves a path relative to the other. You can put this repository anywhere.

## Getting set up

There is no pub workspace. Each `pubspec.yaml` resolves independently, so run
`dart pub get` in the directory you are working in.

```bash
git clone https://github.com/dazacode/swayve-plugins.git
cd swayve-plugins

dart pub get                                    # root: swayve_plugin_tools
cd packages/swayve_plugin_sdk && dart pub get && cd ../..
```

This repository has no plugins of its own to `pub get` into — if you're
working on one, clone
[`Daza-Swayve-plugins`](https://github.com/dazacode/Daza-Swayve-plugins)
beside it and `dart pub get` there instead.

Verify the checkout is healthy before changing anything:

```bash
dart test
```

`tools/validate_plugin.dart --all` has nothing to validate here without a
`--plugins-root` pointing at a `Daza-Swayve-plugins` checkout — see below.

---

## How the SDK is consumed

A plugin's only dependency is `swayve_plugin_sdk`. This repository holds no
plugins of its own any more — `Daza-Swayve-plugins` does — so there is only
one supported way a plugin points at the SDK: a **git dependency**.

(There used to be a second form, a relative `path:` for a plugin living
directly in this repository, back when `plugins/example` and
`plugins/youtube_music` did. It's gone along with them — mentioned here only
so a reader of an old commit isn't confused by it.)

```yaml
dependencies:
  swayve_plugin_sdk:
    git:
      url: https://github.com/dazacode/swayve-plugins.git
      path: packages/swayve_plugin_sdk
      ref: main
```

Pin `ref` to a tag rather than `main` once you cut a release; see
[publishing.md](publishing.md#consuming-a-release).

### Why never a cross-repository path

A `path:` dependency that reaches *out* of its own repository is the wrong
answer, because it encodes where two repositories sit on *one* machine:

```yaml
# Never do this in a committed pubspec.
dependencies:
  swayve_plugin_sdk:
    path: ../../../swayve-plugins/packages/swayve_plugin_sdk
```

That resolves only if the sibling layout is exactly right. It breaks in CI,
breaks for anyone who clones somewhere else, and — worse — it would make a build
depend on this repository existing at a particular path on disk.

The git dependency satisfies both constraints that matter:

| Constraint | How it is satisfied |
|---|---|
| **Delete this repository and the client still builds.** | The client does not depend on the SDK at all. Nothing here is on the client's dependency graph; Swayve Core works with zero plugins. When the host work lands, the client will reference the SDK by URL, so a missing local checkout is irrelevant. |
| **Clone this repository anywhere and plugins still develop.** | A plugin's dependency is a URL and a ref, not a path — it refers to nothing outside its own checkout, so any location on any machine resolves identically, including a CI runner with no sibling directory at all. |

### Working on the SDK and an external plugin at once

If your plugin lives elsewhere and you are changing the SDK in the same session,
a committed git dependency would mean pushing to test. Use a **dependency
override** in `pubspec_overrides.yaml`, which pub reads but which never ships:

```yaml
# pubspec_overrides.yaml — local only, do not commit
dependency_overrides:
  swayve_plugin_sdk:
    path: ../../swayve-plugins/packages/swayve_plugin_sdk
```

Delete it before you package. CI resolves without it, which is the check that
matters.

---

## The loop

### 1 · Edit — works today

Write the provider. Nothing here needs a host:

```dart
final class MyCatalogProvider implements SwayveCatalogProvider {
  MyCatalogProvider(this._http, this._log);
  final SwayveHttpClient _http;
  final SwayvePluginLogger _log;

  @override
  Future<SwayvePage<SwayveAlbum>> albums(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  }) async {
    final response = await _http.get(
      Uri.https('api.example.com', '/albums', {
        'limit': '${request.limit}',
        if (request.cursor != null) 'cursor': request.cursor!,
      }),
      cancel: cancel,
    );
    if (response.statusCode == 429) {
      throw const SwayvePluginRateLimitedException('Upstream is throttling us.');
    }
    return _decodeAlbums(response.bodyAsJson);
  }
  // …
}
```

### 2 · Validate — works today

```bash
dart run tools/validate_plugin.dart ../Daza-Swayve-plugins/my_plugin
dart run tools/validate_plugin.dart ../Daza-Swayve-plugins/my_plugin --strict --json
(cd ../Daza-Swayve-plugins/my_plugin && dart format . && dart analyze)
```

`--strict` turns warnings into errors and is what CI runs, so run it before you
push rather than after. `--json` is for editor integration and scripts; every
diagnostic carries a stable code.

Fix everything before moving on. A manifest error means the host would never
have reached your code anyway.

### 3 · Run a Swayve dev build — **requires host work, not yet implemented**

The intended step: build the client in debug with the plugin registered, and the
plugin becomes available to the app.

```bash
cd ../swayve-client
flutter run --debug
```

This does nothing plugin-related today, because the client has no registry to
register into. What must exist first — a `PluginRegistry`, a fourth
`LibraryKind`, an async `LibraryStore.search`, a widened playback seam — is
specified in [host-integration.md](host-integration.md).

### 4 · Plugin appears in Explore — **requires host work, not yet implemented**

The intended experience: the plugin shows up under Explore's "Your libraries" as
a source alongside *This device*, and its search results appear as their own
group in the search screen. The client already groups song results by source
library through a provider-agnostic mechanism, which is the natural insertion
point — but the plugin-backed library kind that would slot into it does not
exist yet.

### 5 · Test the provider — works today

This is where you should be spending most of your loop regardless, because it is
faster than any of the above and it is the only step that will still be here
after every refactor:

```bash
cd ../Daza-Swayve-plugins/my_plugin && dart test
```

```dart
test('albums paginates with a cursor', () async {
  final context = FakeSwayvePluginContext(
    permissions: {SwayvePermission.network},
  );
  addTearDown(context.close);
  context.fakeHttp.enqueueJson({'items': <Object?>[], 'next': 'CAAQAA'});

  final page = await MyCatalogProvider(context.http, context.log)
      .albums(const SwayveBrowseRequest(limit: 20));

  expect(page.cursor, 'CAAQAA');
  expect(page.hasMore, isTrue);
  expect(context.fakeHttp.requests.single.url.queryParameters['limit'], '20');
});
```

`FakeSwayvePluginContext` enforces the permission set you give it, so a provider
that reaches for storage it did not declare fails in the test rather than on a
user's phone. Full harness reference: [testing.md](testing.md).

---

## Local development of a plugin the host has not shipped

There is a debug-only path for loading a plugin from a local directory during
development. Two things about it are non-negotiable, and both are load-bearing
rather than cautious:

1. **It is compiled out of release builds.** Not disabled by a flag, not gated
   behind a setting a user could find, not behind a hidden gesture — absent from
   the release binary. A code path that can load arbitrary local code is a code
   path an attacker will try to reach, and the only reliable defence is for it
   not to be there.
2. **It never becomes the distribution mechanism.** Its purpose is a tight
   inner loop for someone who already has the source open. A user is never asked
   to "point Swayve at a folder"; that is how sideloading ecosystems begin, and
   it is not what this is.

Consequently: on iOS, this path does not exist even in debug for `bundled`
plugins, because the restriction is about what the runtime can execute, not
about build configuration. See [platforms.md](platforms.md#the-ios-restriction).

**Status: not implemented in v1.** The debug loader is specified host behaviour,
not shipped behaviour. Today the working development path is steps 1, 2 and 5 —
the test harness — and `runtime: compiled` plugins whose source lives in this
repository.

---

## Command reference

| Command | What it does |
|---|---|
| `dart pub get` | Resolve dependencies. Run per directory; there is no workspace. |
| `dart format .` | Format. 80 columns, the Dart default. |
| `dart analyze` | Must report **zero** issues, not "no errors". |
| `dart test` | Tool tests, from the repository root. |
| `cd ../Daza-Swayve-plugins/my_plugin && dart test` | One plugin's tests. Each package resolves its own pubspec, so tests run from inside it — `dart test` has no `--directory` flag. |
| `dart run tools/validate_plugin.dart ../Daza-Swayve-plugins/my_plugin` | Validate one plugin. Takes several directories at once. |
| `dart run tools/validate_plugin.dart --all --plugins-root ../Daza-Swayve-plugins` | Validate every plugin in a `Daza-Swayve-plugins` checkout. `--plugins-root <dir>` changes what `--all` scans; there is no `plugins/` in *this* repo to default to any more. |
| `dart run tools/package_plugin.dart ../Daza-Swayve-plugins/my_plugin --out dist` | Validate, then build a deterministic `.swayveplugin` + `.sha256`. `--key <file>` signs it. |
| `dart run tools/verify_package.dart dist/my_plugin-0.1.0.swayveplugin` | Verify hashes, digest and archive structure. `--pubkey`, `--require-signature` and `--dest` refine it. |

All three tools accept `--json`, `--quiet`, `--strict` and `--help`.
Exit codes: `0` OK · `1` failed · `2` bad usage · `3` internal error.

---

## Before you open a PR

```bash
dart format .
dart analyze
dart run tools/validate_plugin.dart --all --strict --plugins-root ../Daza-Swayve-plugins
dart test                              # from the repo root: swayve_plugin_tools
(cd ../Daza-Swayve-plugins/my_plugin && dart test)
```

CI runs `dart analyze --fatal-infos`, so treat an info as a failure locally too.
Green on all five is the floor, not the bar — see
[CONTRIBUTING.md](../CONTRIBUTING.md) for what else review looks at.

---

## See also

- [testing.md](testing.md) — the fakes, and the acceptance checklist
- [plugin-manifest.md](plugin-manifest.md) — when validation fails and you want the rule
- [publishing.md](publishing.md) — cutting a release
- [host-integration.md](host-integration.md) — the work steps 3 and 4 are waiting on
