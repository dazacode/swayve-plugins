# swayve-plugins

[![validate](https://github.com/dazacode/swayve-plugins/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/dazacode/swayve-plugins/actions/workflows/validate.yml)
[![test](https://github.com/dazacode/swayve-plugins/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/dazacode/swayve-plugins/actions/workflows/test.yml)

The plugin **platform** for **Swayve**: the SDK, the manifest schema, and the
validation/packaging/verification tooling. This repository provides the
tools; it does not itself contain any plugins.

**Looking for a plugin to read?** [`swayve-plugin-example`](https://github.com/dazacode/swayve-plugin-example)
is the reference: a complete, tested, fully offline plugin, plus a manifest
reference covering every field the schema defines. Plugins depend on this
repository for the SDK and, in CI, for these tools; this repository depends on
no plugin and never will — the platform doesn't need to know what plugins exist
to work.

A Swayve plugin teaches Swayve about a music source it did not previously know
about. It answers questions — "what matches this search?", "what is on this
album?", "how do I play this track?" — and Swayve renders the answers using the
same UI it uses for everything else. The plugin supplies **data**; the host
supplies **experience**.

Swayve Core works with zero plugins installed. Nothing in this repository is
required for the Swayve client to build or run. You can delete this repository
and the client still compiles.

---

## What a plugin is

A plugin is a Dart package that declares a manifest (`plugin.json`), implements
one or more **provider interfaces** from `package:swayve_plugin_sdk`, and talks
to its own external service directly from the user's device.

```dart
final class MySearchProvider implements SwayveSearchProvider {
  MySearchProvider(this._http);
  final SwayveHttpClient _http;

  @override
  Future<SwayveSearchResult> search(
    SwayveSearchQuery query, {
    SwayveCancellationToken? cancel,
  }) async {
    final response = await _http.get(
      Uri.https('api.example.com', '/search', {'q': query.text}),
      cancel: cancel,
    );
    return SwayveSearchResult(tracks: _decodeTracks(response.bodyAsJson));
  }
}
```

The host never learns that this provider is "the Example plugin". It asks the
registry for everything implementing `SwayveSearchProvider` and merges the
results.

## What a plugin is **not**

| Not a… | Why |
|---|---|
| **Theme engine** | Plugins cannot change Swayve's colours, typography, spacing or layout. There is no styling surface, by design. |
| **Way to redesign the app** | Plugins return models, not widgets. There is no Flutter widget injection in v1, and the SDK has no Flutter dependency at all. |
| **Proxy service** | Swayve runs no per-plugin backend. Every request a plugin makes leaves the user's own device, under the user's own IP and credentials. |
| **Way to ship arbitrary code to iOS** | Swayve cannot download and execute arbitrary Dart or native code on iOS. `runtime: bundled` carries declarative data only, and the validator hard-errors on `bundled` + `ios`. See [docs/platforms.md](docs/platforms.md). |
| **Background agent** | Background execution is not a grantable permission in v1. A plugin runs when the host calls it, and only then. |
| **Route into the user's library** | A plugin cannot read the user's music files, Swayve account credentials, other plugins' storage, or arbitrary filesystem paths. See [docs/permissions.md](docs/permissions.md). |

## Repository layout

```
swayve-plugins/
├── docs/                         # the specification you are reading a summary of
├── schema/
│   └── swayve-plugin.schema.json # JSON Schema (draft 2020-12) for plugin.json
├── packages/
│   └── swayve_plugin_sdk/        # the public SDK — pure Dart, zero runtime deps
├── tools/                        # validate_plugin · package_plugin · verify_package
├── lib/                          # implementation behind tools/
└── test/                         # tool tests and fixtures
```

No `plugins/` directory here — see the note at the top of this README. Every
example below that names a plugin directory assumes you have a plugin checkout
alongside this one, since that's where a real `plugin.json` to point these
tools at actually lives. Clone [`swayve-plugin-example`](https://github.com/dazacode/swayve-plugin-example)
if you need one.

There is **no pub workspace**. Each `pubspec.yaml` resolves independently — run
`dart pub get` in the directory you are working in. The root `pubspec.yaml` is
the `swayve_plugin_tools` package and owns `lib/`, `tools/` and `test/`.

## Your first plugin in 60 seconds

There is no scaffolding generator. Copying the reference plugin from
[`swayve-plugin-example`](https://github.com/dazacode/swayve-plugin-example) is the
supported path, and it is deliberately small enough to read end to end.

```bash
git clone https://github.com/dazacode/swayve-plugins.git
git clone https://github.com/dazacode/swayve-plugin-example.git  # the reference plugin
cd swayve-plugins
dart pub get                                   # tooling deps, at the repo root

cp -r ../swayve-plugin-example/example ../my_plugin   # 1. copy the reference plugin
cd ../my_plugin && dart pub get && cd ../../swayve-plugins
```

Then edit three things in `my_plugin/plugin.json`:

```jsonc
{
  "id": "dev.yourname.swayve.my_plugin",  // reverse-DNS, ≥3 segments
  "entrypoint": "my_plugin",              // MUST equal the directory name
  "name": "My Plugin"
}
```

and validate:

```bash
dart run tools/validate_plugin.dart ../my_plugin
(cd ../my_plugin && dart test)
```

Then rename the entrypoint function in `lib/` and update `examplePluginId`.
`entrypoint` matching the directory name is rule 7 of the manifest validator and
is an **error**, not a warning — it is the single most common first failure. Note
that `entrypoint` names the directory and the Dart library, **not** the factory
function: `youtube_music` declares `"entrypoint": "youtube_music"` and
exports `createYouTubeMusicPlugin()`, because `youtube_music()` would violate
`non_constant_identifier_names`.

The full field reference is in [docs/plugin-manifest.md](docs/plugin-manifest.md);
the edit → validate → run loop is in [docs/development.md](docs/development.md).

Every plugin depends on the SDK by a **pinned git dependency** — never a path
that reaches across repositories, since no plugin repository can rely on
sitting next to this one on disk:

```yaml
dependencies:
  swayve_plugin_sdk:
    git:
      url: https://github.com/dazacode/swayve-plugins.git
      path: packages/swayve_plugin_sdk
      ref: <commit sha>       # pin a commit, not a floating branch
```

### Getting a `compiled` plugin into a host app

Depending on the SDK is what lets your plugin *compile*. It is not what makes
it *run* — a `compiled` plugin's code has to be linked into a specific host
binary (that's what makes it iOS-safe; see
[docs/platforms.md](docs/platforms.md)), and that linking is a separate,
explicit step, never automatic discovery.

For a first-party plugin, that step is one dependency and one map entry in a
`swayve_plugin_registry` package — not a new dependency in every host app that
wants it. That package lives with the plugins it catalogues rather than here:
the platform has no business knowing which plugins exist. A host depends on it
once, permanently, no matter how many plugins exist; it reads
`firstPartyCompiledPlugins[manifestId]` to find the factory for a verified
bundle. See that package's README for the two-line process, and
[docs/platforms.md § How a `compiled` plugin actually gets activated](docs/platforms.md#how-a-compiled-plugin-actually-gets-activated)
for how a community or self-hosted build composes its own additions in
without forking anything.

## Capabilities

A capability is a *question the plugin can answer*. Each maps 1:1 to one
provider interface — never one large interface.

| Capability | Provider interface | Host uses it for |
|---|---|---|
| `search` | `SwayveSearchProvider` | Merging results into the Explore search screen |
| `catalog` | `SwayveCatalogProvider` | Browsing albums, artists and tracks from the source |
| `streaming` | `SwayveStreamProvider` | Resolving a track to something playable |
| `metadata` | `SwayveMetadataProvider` | Enriching a track the host already has |
| `lyrics` | `SwayveLyricsProvider` | Showing plain or time-synced lyrics |
| `scrobbling` | `SwayveScrobbleProvider` | Reporting now-playing and completed plays |
| `authentication` | `SwayveAuthProvider` | Signing the user in to the plugin's service |
| `webview` | *(none — host facility, via `SwayveWebViewController`)* | Auth flows and embedded playback surfaces |
| `artwork` | `SwayveArtworkProvider` | Fetching cover images at a requested size |
| `playlist_read` | `SwayvePlaylistProvider` | **No host consumer yet** — the client has no playlist type |

Full signatures and host semantics: [docs/capabilities.md](docs/capabilities.md).

## Permissions

A permission is a *facility the plugin may touch*. Capabilities and permissions
are separate on purpose: what you can answer is not what you may reach for.

| Permission | Grants | Does not grant |
|---|---|---|
| `network` | Outbound HTTP(S) through `SwayveHttpClient`, restricted to `network.hosts` | Raw sockets, arbitrary hosts, listening |
| `webview` | Host may render a plugin-requested web view | Injecting script into the host UI |
| `external_auth` | Host-mediated auth flow + the plugin's own credential slot | Swayve account credentials |
| `local_plugin_storage` | Read/write in the plugin's own isolated key/value namespace | Any other plugin's namespace, or the filesystem |
| `clipboard` | **Write** to the system clipboard | Reading the clipboard, ever |

The validator relates the two vocabularies with two rules of very different
strength:

- **Error** — `webview` requires the `webview` permission, and `authentication`
  requires `external_auth`. In both cases the capability and the permission
  describe the same act, so one without the other describes a plugin that
  cannot do what it says.
- **Info** — the other eight capabilities *usually* reach the network, so
  declaring one without `network` is a note, never a failure. Whether a plugin
  opens a connection is not decidable from a manifest: the reference plugin
  declares `search` and `catalog`, serves a catalogue compiled into itself, and
  honestly declares **zero permissions**. Real
  enforcement is at runtime, where
  the answer is knowable — `context.http` throws
  `SwayvePermissionDeniedException` without the permission, in your own tests.

Over-declaring is the direction that costs a user trust, so *that* is a warning
`--strict` promotes. `local_plugin_storage` and `clipboard` are host facilities
no capability could imply, so declaring them never warns.

Not grantable in v1 at all: the user's music files, Swayve account credentials,
other plugins' storage, arbitrary filesystem paths, device secrets, background
execution. Details: [docs/permissions.md](docs/permissions.md).

## Tooling

Three commands. Run them from the repository root after `dart pub get`.

### `validate_plugin`

```bash
dart run tools/validate_plugin.dart ../my_plugin
```

```
../my_plugin
  ERROR   capabilities: 'webview' requires permission 'webview'   (plugin.json:15)
  WARNING network: permission declared but no network.hosts listed
  INFO    version 0.1.0 is pre-1.0; the plugin API surface is unstable
2 problems (1 error, 1 warning)
```

Info notes are not problems and are left out of the count. `--all` validates
every directory under `--plugins-root <dir>` (defaults to `plugins`, which
doesn't exist in this repo any more — point it at a directory of plugins,
e.g. `--all --plugins-root ../plugins`).

### `package_plugin`

```bash
dart run tools/package_plugin.dart ../my_plugin --out dist
```

Validates first and refuses to package anything that fails. Emits a
deterministic `dist/my_plugin-0.1.0.swayveplugin` alongside
`dist/youtube_music-0.1.0.sha256`. Pass `--key path/to/ed25519.key` to produce a
signed `signature.json` inside the archive.

### `verify_package`

```bash
dart run tools/verify_package.dart dist/youtube_music-0.1.0.swayveplugin
```

Checks the archive the way a host must before unpacking it: extraction safety
first, then integrity, then signature. Add `--pubkey <file|base64>` to verify
against a key you decided to trust, `--require-signature` to fail an unsigned
bundle rather than note it, and `--dest <dir>` to test path containment against
the directory you will actually unpack into.

All three accept `--json` (machine-readable report with stable diagnostic codes
such as `capability_requires_permission` and `entry_escapes_root`), `--quiet`,
`--strict` (warnings become errors; this is what CI uses) and `--help`.

| Exit code | Meaning |
|---|---|
| `0` | OK |
| `1` | Validation or verification failed |
| `2` | Bad usage |
| `3` | Internal error |

## The plugin catalogue

There isn't one here, and there is not meant to be. This repository is the
platform: the SDK, the schema, the tooling and the specification. Which plugins
exist, who wrote them and what they integrate with is not its business — a
platform that enumerated its plugins would have to be edited every time one
appeared.

A `runtime: compiled` plugin's source is compiled into a Swayve build through
the SDK interfaces only; nothing is downloaded at runtime. The host reaches its
compiled plugins through a registry package that lives with those plugins, not
here.

To read one, start with [`swayve-plugin-example`](https://github.com/dazacode/swayve-plugin-example).

## Status

This is the **foundation**, not a finished product.

- The SDK, schema, validator, packager and verifier are the deliverable here.
- **The Swayve client does not yet have a plugin system.** There is no loader,
  no registry and no extension point in the client today.
  [docs/host-integration.md](docs/host-integration.md) is the specification of
  the work the client must still do, written against a survey of the real
  client code.
- `bundled` runtime carries declarative data only, and no host loads a bundle
  today on any platform.
- Ed25519 signing is **live**, not stubbed — `package_plugin --key` really signs
  and `verify_package --pubkey` really verifies. What does not exist is anything
  that tells you *which* key to trust: no key server, no trust store, no
  revocation, and no plugin registry. See
  [docs/publishing.md](docs/publishing.md).

## Documentation

| Document | Read it when |
|---|---|
| [architecture.md](docs/architecture.md) | You want to know where the host ends and the plugin begins |
| [plugin-manifest.md](docs/plugin-manifest.md) | You are writing or debugging `plugin.json` |
| [permissions.md](docs/permissions.md) | You are deciding what to declare, or reviewing what someone else declared |
| [capabilities.md](docs/capabilities.md) | You are implementing a provider interface |
| [packaging.md](docs/packaging.md) | You care about `.swayveplugin`, integrity or signatures |
| [platforms.md](docs/platforms.md) | You are wondering why iOS says no |
| [development.md](docs/development.md) | You want the edit → validate → run loop |
| [testing.md](docs/testing.md) | You are writing tests without a host |
| [publishing.md](docs/publishing.md) | You are cutting a release |
| [versioning.md](docs/versioning.md) | You are changing a version number, any of the four |
| [host-integration.md](docs/host-integration.md) | You are implementing the host side in the Swayve client |

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a plugin PR. Compiling is
not sufficient for acceptance.

Security reports go through the private channel in [SECURITY.md](SECURITY.md),
never a public issue.

## License

Apache-2.0. Copyright 2026 Swayve. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
