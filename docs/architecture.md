# Architecture

This document describes the boundary between the Swayve host and a plugin: what
crosses it, in which direction, and why it was drawn where it was.

## The shape of the system

```
┌──────────────────────────────────────────────────────────────────────┐
│  Swayve Core                                                         │
│                                                                      │
│  Explore · Library · Player · Settings · Downloads                   │
│  ── renders ALL UI, owns ALL user data, owns the audio pipeline ──   │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ provider interfaces only
                                │ (never a plugin id, never a widget)
┌───────────────────────────────▼──────────────────────────────────────┐
│  Plugin Runtime                                                      │
│                                                                      │
│  registry · permission enforcement · timeouts · error isolation      │
│  host facilities: SwayveHttpClient · SwayvePluginStorage ·           │
│                   SwayveCredentialStore · SwayveWebViewController ·  │
│                   SwayveSettingsView · SwayvePluginLogger            │
└───────┬────────────────────────────────┬─────────────────────────────┘
        │                                │
┌───────▼──────────────┐        ┌────────▼─────────────┐
│  Plugin A            │        │  Plugin B            │
│  youtube_music       │        │  example             │
│  implements          │        │  implements          │
│  Search/Catalog/     │        │  Search/Catalog      │
│  Stream/Artwork      │        │                      │
└───────┬──────────────┘        └────────┬─────────────┘
        │ HTTPS from the user's device   │
┌───────▼──────────────┐        ┌────────▼─────────────┐
│  music.youtube.com   │        │  (in-repo fixture,   │
│  *.googlevideo.com   │        │   no network)        │
│  i.ytimg.com         │        │                      │
└──────────────────────┘        └──────────────────────┘
```

Two properties of that picture matter more than the boxes:

1. **Swayve hosts no per-plugin backend.** The arrow from a plugin to its
   external service leaves the user's device directly. There is no Swayve proxy
   in the path, so there is no Swayve infrastructure to scale, no Swayve
   liability for the traffic, and no Swayve server that sees the user's
   listening. A plugin that needs a server is a plugin whose author runs that
   server.
2. **Nothing flows upward except data.** A plugin hands the runtime normalized
   models. It never hands the host a widget, a colour, a route, or a string the
   host will execute.

## Why the SDK is pure Dart with no Flutter dependency

`package:swayve_plugin_sdk` depends on `package:meta` and nothing else. No
`flutter`, no `dart:ui`, no `dart:io`.

The obvious alternative — let plugins ship Flutter widgets — dies on a concrete
fact about the client. The Swayve client imports
`package:material_ui/material_ui.dart`, **not** `package:flutter/material.dart`,
and bridges the five SDK-Material dependencies through a
`MaterialUiCompatibilityBridge` in `lib/app/app.dart`. A widget-shaped SDK would
therefore have to pick one of:

- depend on SDK Material, and hand plugin authors a widget vocabulary that does
  not match the app they are extending; or
- depend on `material_ui`, and drag a specific UI library into a public
  third-party API surface forever.

Both are bad. Staying pure Dart sidesteps the question entirely, and buys three
further things: plugin tests run under `dart test` with no Flutter toolchain,
the SDK can be analysed and versioned independently of the client's Flutter
version, and the "plugins supply data, the host renders UI" rule is enforced by
the type system rather than by review.

A widget surface is **not implemented in v1** and is not a near-term plan.

### On the `Swayve` prefix

The client does not prefix its own classes — it uses `Track`, `Album`, `Artist`,
`App*` for design tokens, `Music*` for media UI. The SDK does the opposite and
prefixes everything `Swayve*`. That is deliberate: SDK types are imported
*alongside* the host's own types in the mapping layer, and a file that contains
both `Track` and `SwayveTrack` reads correctly, while a file that contains two
`Track`s does not. The prefix is the price of being a public API rather than an
internal one.

## Capabilities and permissions are different questions

| | Capability | Permission |
|---|---|---|
| Question | *What can this plugin answer?* | *What may this plugin touch?* |
| Audience | The host's feature routing | The host's enforcement layer |
| Example | `search` | `network` |
| Consequence of adding one | Host asks you more questions | Host hands you more power |

Collapsing them into one list is tempting and wrong. `search` and `lyrics` both
need `network`, so a merged list would either force the host to grant network
access per feature (nonsense) or make `network` implicit and invisible (worse —
the user could no longer be told what a plugin reaches for). Separation also
lets the validator do something useful: capabilities *imply* permissions, so a
plugin that declares `network` while implementing nothing that needs it gets a
warning for over-permissioning. That check is only possible because the two
vocabularies are independent.

There is a third property the split gives you: a capability can exist with no
host consumer yet (`playlist_read` today) without that dangling capability
implying any grant of power beyond `network`.

## One provider interface per capability

There is no `SwayvePlugin.doEverything()`. `search` maps to
`SwayveSearchProvider`, `lyrics` to `SwayveLyricsProvider`, and so on — ten
capabilities, ten interfaces, registered individually:

```dart
@override
Future<void> initialize(SwayvePluginContext context) async {
  context.registerSearchProvider(MySearchProvider(context.http));
  context.registerCatalogProvider(MyCatalogProvider(context.http));
}
```

A single fat interface would force every plugin to implement — or stub, or throw
from — methods it has no business having. `UnimplementedError` would become the
most common expression in the ecosystem, and the host would have to discover
capability by calling and catching. With one interface per capability, the
registry *is* the capability index:

```dart
final searchers = pluginRegistry.providers<SwayveSearchProvider>();
```

If that list is empty, no plugin can search; the host does not need to ask, and
a plugin cannot lie about it. It also means adding an eleventh capability later
adds a new interface rather than a breaking change to an existing one.

## The host renders all UI

Plugins return `SwayveTrack`, `SwayveAlbum`, `SwayveSearchResult`,
`SwayvePlayableSource`. The host renders them with the widgets it already has —
`MusicTrackRow`, `AlbumTile`, `ArtistTile`, `MediaShelf`, `MusicArtwork`,
`StatusLabel`. This is why a plugin cannot make Swayve look wrong, why plugin
content is accessible and themed for free, and why a plugin can be written by
someone who has never opened Flutter.

Settings are the sharpest case: a plugin *describes* its settings in the
manifest as a list of typed descriptors, and the host renders the settings page.
The plugin never draws its own settings UI, never receives a build context, and
never sees a tap. See [plugin-manifest.md](plugin-manifest.md#settings).

## The architectural test that matters most

**The client must never branch on a plugin id.** Everything else in this
document is downstream of that rule. If you can find a plugin id in a `switch`,
an `if`, a feature flag, or a `Map<String, Widget>` in the client, the
architecture has already failed and adding plugin number three will hurt.

```dart
// WRONG — the host now knows what YouTube Music is.
// Adding a second streaming plugin means editing this function.
// Removing the plugin means editing this function.
// The plugin's behaviour is defined in the host, not in the plugin.
if (plugin.id == 'app.swayve.plugins.youtube_music') {
  results.addAll(await youTubeSearch(query));
}
```

```dart
// RIGHT — the host knows only "things that can search".
// Zero plugins works. Five plugins works. Deleting one works.
final results = await Future.wait([
  for (final provider in pluginRegistry.providers<SwayveSearchProvider>())
    _guarded(() => provider.search(query)),
]);
```

The same rule applies to playback (`providers<SwayveStreamProvider>()`, not
"if it's a YouTube URL"), to artwork, and to how plugin-backed sources appear in
Explore — which is why the client's existing `_groupBySource(...)` grouping is
the right insertion point: it already buckets by library id rather than by
provider identity. See [host-integration.md](host-integration.md).

When a plugin genuinely needs the host to do something unusual, the answer is a
new capability or a new field on a model — something *every* plugin can use —
not a special case.

## Lifecycle

```
discover → readManifest → validateSchema → verifyIntegrity → checkCompatibility
        → resolvePermissions → load → initialize → registerProviders → active
        → (degraded | disabled) → dispose
```

Every stage can fail, and every failure must produce a specific, user-readable
reason. Never a stack trace, never a crash, never a silent disappearance.

| # | Stage | What it does | What failure means to the user |
|---|---|---|---|
| 1 | `discover` | The host enumerates candidate plugins — compiled-in registrations and, where supported, bundles on disk. | The plugin simply is not listed. Nothing is shown, because nothing was found. |
| 2 | `readManifest` | Read and JSON-parse `plugin.json`. | *"This plugin could not be read."* Almost always a corrupt download or a hand-edited manifest. |
| 3 | `validateSchema` | Check the manifest against the JSON Schema and the ten cross-field rules. | *"This plugin's configuration is not valid."* The developer sees the specific rule; the user sees one sentence. |
| 4 | `verifyIntegrity` | Recompute file hashes and the bundle digest; check the signature if present. | *"This plugin failed its integrity check and was not loaded."* This is a security stop, not a warning — the host must not offer "load anyway". |
| 5 | `checkCompatibility` | In order: `schemaVersion` → `swayvePluginApi` vs host → `minimumSwayveVersion` vs host version → `platforms` contains host platform → `runtime` supported on host platform. | The most specific reachable message wins, e.g. *"YouTube Music requires a newer version of Swayve."* or *"YouTube Music is not available on this device."* See [versioning.md](versioning.md). |
| 6 | `resolvePermissions` | Turn declared permissions into the concrete facilities the context will expose. Undeclared facilities throw `SwayvePermissionDeniedException` on access. | Nothing user-visible on success. On refusal, the plugin is disabled with the reason naming the permission. |
| 7 | `load` | Materialise the plugin object via its `SwayvePluginFactory`. | *"&lt;Plugin name&gt; — Temporarily unavailable."* A throwing factory is a defect, not a configuration problem. |
| 8 | `initialize` | Call `SwayvePlugin.initialize(context)`, bounded by `SwayveTimeouts.initialize` (8s). | Same message. A slow `initialize` is treated as a failed `initialize`; the host does not wait for a plugin that will not answer. |
| 9 | `registerProviders` | Collect whatever the plugin registered during `initialize`. A capability declared but never registered is a defect the host reports. | If nothing registered, the plugin is present but inert; the host shows it as unavailable rather than pretending it works. |
| 10 | `active` | The plugin's providers participate in search, browse, playback and the rest. | This is the only state in which the user sees plugin content. |
| 11 | `degraded` | Entered when an active plugin throws or times out. The plugin stays loaded; its results stop being merged. | *"&lt;Plugin name&gt; — Temporarily unavailable"* rendered with the host's `StatusLabel`. Everything else in Swayve keeps working — this is the whole point of the state. |
| 12 | `disabled` | The user turned it off, or a stage 3–6 failure was permanent. | The plugin appears in settings with its reason, and contributes nothing. |
| 13 | `dispose` | `SwayvePlugin.dispose()`, bounded by `SwayveTimeouts.dispose` (3s). | Nothing user-visible. A plugin that hangs in `dispose` is abandoned, not waited on. |

A plugin that throws during *any* phase moves to `degraded`. It never takes a
screen, a query, or the app down with it. See
[host-integration.md](host-integration.md#failure-isolation-and-timeouts) for
the host obligations that make that guarantee real.

## Related reading

- [capabilities.md](capabilities.md) — the ten interfaces in detail
- [permissions.md](permissions.md) — the enforcement model
- [platforms.md](platforms.md) — why `compiled` and `bundled` exist
- [host-integration.md](host-integration.md) — what the client must build
