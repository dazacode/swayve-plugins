# Host integration

**This is a specification of work the Swayve client must still do.** It is not a
description of an existing system.

There is no plugin system in the client today: no loader, no registry, no
extension points. Every occurrence of the word "plugin" in the client's `lib/`
refers to a Flutter platform plugin. Nothing in this document can be called
against the client as it stands.

It is written in "the host must…" voice, and it is written against a survey of
the real client code (2026-08-15). File and line references point at the client
repository (`music_sync`, version `1.1.0+2`, Dart `^3.12.2`,
`flutter_lints ^6.0.0`) and are cited so that each requirement can be traced to
the code it constrains. Line numbers drift; the symbols are the durable part.

---

## Naming, before anything else

The client's reverse-DNS root for native identifiers is **`dev.seanmusic`** —
Android `dev.seanmusic.music_sync`, iOS `dev.seanmusic.musicSync`. Only
user-facing strings say "Swayve".

Plugin **ids** nonetheless use the `app.swayve.plugins.` namespace, as specified
throughout these docs. That is a plugin-registry namespace, not a bundle id, and
the two never need to agree. The host must not derive one from the other, and
must not assume a plugin id shares a prefix with the app.

The host must also not introduce code generation to consume the SDK. The client
has none — no `freezed`, no `json_serializable`, no `build_runner` — and
serialization is hand-written `toJson`/`fromJson` throughout. The SDK matches
this deliberately. The mapping layer described below is hand-written too.

---

## 1 · The registry

**The host must expose plugin functionality only through provider interfaces,
never through plugin identity.**

The client must gain a registry whose entire query surface is by type:

```dart
// The only shape of lookup the rest of the client is permitted to use.
Iterable<T> providers<T>();
```

Every consumer — search, browse, playback, artwork — resolves through this. No
consumer may accept, store, compare or switch on a plugin id. If a plugin id
appears anywhere outside the registry and the settings screen that lists
installed plugins, the requirement has been violated.

```dart
// WRONG — the client now contains Nebula Music's behaviour.
if (plugin.id == 'app.swayve.plugins.nebula_music') { … }

// RIGHT — the client contains "things that can search".
for (final p in registry.providers<SwayveSearchProvider>()) { … }
```

The host must additionally:

- run the [lifecycle](architecture.md#lifecycle) in order, with a specific
  user-readable reason at each rejection point;
- apply the [compatibility checks](versioning.md#the-compatibility-check-order)
  in the specified order;
- enforce declared permissions when constructing each plugin's
  `SwayvePluginContext`, throwing `SwayvePermissionDeniedException`
  synchronously on undeclared access. The SDK ships a reference enforcement
  mixin; the host must use it rather than reimplement the rule, so that
  `FakeSwayvePluginContext` and the host cannot drift apart.

Registration for `runtime: compiled` plugins happens at app build time via
each plugin's `SwayvePluginFactory`. The host must not special-case which
factories exist, and it must not depend on individual first-party plugin
packages directly — that does not scale past one plugin. Depend on a
`swayve_plugin_registry` package instead — it lives with the plugins it
catalogues, not in this repository — and resolve a verified bundle's manifest
id against `firstPartyCompiledPlugins` from it. See
[platforms.md § How a `compiled` plugin actually gets activated](platforms.md#how-a-compiled-plugin-actually-gets-activated)
for the full mechanism, including how a private fork adds a plugin the
first-party registry does not carry.

---

## 2 · Model mapping

The SDK's models do not match the client's, and the gaps are not cosmetic. The
host must write an explicit mapping layer; it must not change the SDK models to
match the client, because the SDK is a public surface and the client's shapes
are internal decisions.

### `SwayveTrack` → `Track`

Client `Track` lives at `lib/core/models/track.dart:33`. The mismatch is
substantial:

| SDK | Client | The host must |
|---|---|---|
| `artists: List<SwayveArtistRef>` | `artist: String` (single) | Join with `", "` at the mapping boundary — and nowhere else. The list is the source of truth; the string is a rendering of it. |
| `artists.first` | `albumArtist: String` | Use the first artist as `albumArtist`. This matters more than it looks: album grouping keys off it (below). |
| `id: SwayveMediaId` | `hash` (required) | Synthesise a stable `hash` from `SwayveMediaId.uri` (`swayve://<pluginId>/<encoded value>`). It must be deterministic — the same track must produce the same hash across sessions — and it must not collide with a local file's hash. |
| `duration: Duration?` | `duration` (required) | Supply a value. A plugin may not know it; the host must decide on a representable "unknown" rather than dropping the track. |
| — | `format` (required) | Derive from `SwayvePlayableSource.mimeType` where a source has been resolved, and otherwise carry a defined placeholder. It is a required field with no plugin-side equivalent. |
| — | `fileSize` (required) | Same problem. A streamed track has no meaningful file size until it is downloaded. |
| — | `dateAdded`, `lastModified` (required) | Host-assigned. These are facts about the user's library, not about the source. |
| `availability` | `syncState` | Set `syncState: SyncState.remote` for plugin-sourced tracks. |

The four required fields with no plugin-side equivalent — `format`, `fileSize`,
`dateAdded`, `lastModified` — are the concrete cost of `Track` having been
designed for local files. The host must decide, once and centrally, what they
hold for a remote track. Scattering that decision across call sites is how the
same track ends up with two hashes.

### `SwayveAlbum` → `Album`, `SwayveArtist` → `Artist`

Client `Album` (`lib/core/models/collections.dart:38`) and `Artist`
(`collections.dart:74`) are **derived, not stored**. They are built by
`groupIntoAlbums(List<Track>)` and `groupIntoArtists(...)`, and album identity
is the key `'${albumArtist} ${album}'.toLowerCase()`.

This is a real architectural obstacle, not a mapping detail. A plugin returns
album objects with their own ids; the client has no way to hold an album that
did not come from grouping tracks. The host must pick one:

1. **Project through tracks.** Fetch the album's tracks, map them, and let
   `groupIntoAlbums` reconstruct the album. Preserves the existing invariant;
   costs a round trip, and loses any album-level data the plugin had (year,
   artwork, track count) unless it is smeared onto every track.
2. **Add a construction path.** Allow an `Album` to be built directly from a
   plugin album, bypassing grouping. Keeps plugin data intact; means `Album`
   instances no longer all come from one place, and the derived key stops being
   the sole identity.

Option 2 is the better long-term answer and the larger change. Whichever is
chosen, the host must be aware that plugin albums whose `albumArtist` collides
with a local album's will merge under the derived key — two different albums
becoming one is a silent data bug, so the key must be namespaced by source
before any plugin album enters the grouping path.

The same applies to `Artist` via `groupIntoArtists`.

### `SwayvePlaylist` → nothing

**The client has no `Playlist` type.** No class, no table, no route, no screen.

`playlist_read` is therefore a capability with no host consumer, and
`SwayveSearchResult.playlists` has nowhere to go. The host must ignore playlist
results rather than half-render them, and must not treat a plugin that provides
playlists as broken. Building playlist support is a client feature in its own
right, and the plugin surface is ready for it whenever that happens.

### `SwayveAvailability` → `TrackStanding` / `TrackAvailability`

The client has `TrackStanding` and
`enum TrackAvailability { onDevice, streamable, unavailable }`
(`lib/core/models/track_availability.dart:18` and `:58`), with *permission*
held separately in `LibraryGrant.allowStreaming` / `allowDownload` /
`expiresAt`.

The concepts are close, and conflating them will cause bugs. `SwayveAvailability`
carries three **independent booleans**; `TrackAvailability` is a **3-way enum**
that cannot express "downloadable but not streamable" or "on-device and no
longer streamable". The host must map, not equate:

| From the plugin | To the client |
|---|---|
| `onDevice: true` | `TrackAvailability.onDevice` |
| `streamable: true`, not on device | `TrackAvailability.streamable` |
| neither | `TrackAvailability.unavailable` |
| `downloadable` | **not representable in the enum** — belongs with `LibraryGrant.allowDownload`, which is permission, not availability |

The host must not derive one plugin boolean from another when mapping back, and
must keep the plugin's three facts intact upstream of the enum so that a future
richer client model does not have to recover information the mapping threw away.

---

## 3 · Surfacing a plugin as a library

`MusicLibrary` (`lib/core/models/music_library.dart:173`) with
`enum LibraryKind { thisDevice, myComputer, sharedLibrary }` is how Explore's
"Your libraries" is populated. `MobileController.libraries`
(`lib/mobile/mobile_controller.dart:192`) hard-codes that composition from
`_devices`.

**The host must add a fourth `LibraryKind` — `pluginSource` is the proposed
name — and change the composition** so `libraries` is assembled from devices
*and* from registered plugins, rather than devices alone.

Requirements on that change:

- A plugin-backed library must be a `MusicLibrary` like any other, so that every
  existing consumer of `libraries` works unchanged.
- The library's identity must come from the plugin's id, but consumers must key
  off the **library id**, not the plugin id. This is what keeps the grouping
  described below provider-agnostic.
- A plugin in `degraded` must still appear, marked unavailable, rather than
  disappearing from the list. A library that vanishes and reappears is worse
  than one that says it is having trouble.
- Zero plugins must produce exactly today's list. This is acceptance test A.

---

## 4 · Search

`LibraryStore.search(String)` (`lib/core/services/library_store.dart:396`) is
the single aggregation point, returning
`SearchResults { List<Track> tracks; List<Album> albums; List<Artist> artists; }`
(`:586`). It is a case-insensitive `contains` over local lists —
**synchronous, with no async sources**.

Explore already groups song results by source library via `_groupBySource(...)`
(`lib/features/explore/explore_screen.dart:465`) into
`_SourceGroup { label, tracks }`, bucketed by `MusicLibrary.thisDeviceId` or the
owning device id.

Two things follow, and they pull in opposite directions:

**The good news.** `_groupBySource` is already provider-agnostic — it keys off
library id, not provider identity. Plugin results become additional buckets with
no change to the grouping logic and no plugin-specific branch anywhere in the
search screen. This is precisely what acceptance test F requires, and the
insertion point already exists.

**The required change.** `LibraryStore.search` must become **asynchronous**.
Today it cannot await anything, and every plugin search is a network call. The
host must:

- change the signature to return a `Future` or, better, a `Stream` of
  progressively-completing results, so local matches render immediately and
  plugin buckets fill in as they arrive;
- fan out to `registry.providers<SwayveSearchProvider>()` in parallel, never
  serially — total latency must be the slowest provider, not their sum;
- bound each provider call independently and let a slow or failing provider
  degrade only its own bucket;
- honour cancellation on every keystroke by passing a `SwayveCancellationToken`
  that is cancelled when the query changes;
- render `SwayveSearchResult.partial == true` as a visible "may be incomplete"
  state rather than silently presenting a truncated answer as exhaustive.

Making a synchronous, locally-backed search async is the largest single
refactor this specification asks for, and it touches every current caller of
`LibraryStore.search`.

---

## 5 · The playback seam

This is the tightest constraint in the whole integration.

`PlayerController._sourceFor(Track)`
(`lib/core/services/player_controller.dart:667`) resolves a track to a
`just_audio` `AudioSource` in exactly two ways: `AudioSource.file(localPath)`
when `track.isPlayableOffline`, and otherwise `AudioSource.uri(uri)` from a
single injected seam:

```dart
typedef RemoteAudioResolver = Uri? Function(Track track);   // player_controller.dart:17
player.remoteResolver = controller.streamUriFor;            // app/app.dart:265 — the ONLY assignment
```

So today a playable is **a file path or a bare `Uri`** — no headers, no expiry,
no embed. `SwayvePlayableSource` carries all three, and none of them fits
through a `Uri? Function(Track)`.

**The host must widen this seam.** The resolver must become asynchronous and
must return a richer value carrying at least:

| From `SwayvePlayableSource` | Why the current typedef cannot carry it |
|---|---|
| `headers: Map<String, String>` | Many sources require an `Authorization`, `Referer` or `Cookie` header. `AudioSource.uri` accepts headers; the seam does not pass any. |
| `expiresIn: Duration?` | Signed URLs expire. The host must re-resolve rather than replay a stale URL, which means it must know the URL has a lifetime. |
| `kind: SwayvePlayableKind` | `hlsUrl` and `dashUrl` are not interchangeable with `directUrl` for the player's configuration. |
| `embed: SwayveWebEmbed?` | A `webEmbed` source is not an `AudioSource` at all — it is a different playback surface entirely, and the seam has no way to express "this does not play through just_audio". |
| `mimeType: String?` | Needed to pick a decoder path, and it is the only plausible source for the client `Track.format` field. |

`SwayveWebEmbedKind.inAppWebView` maps onto the client's existing
**`webview_flutter ^4.14.1`** dependency, which is already present — so the
embed path needs new plumbing, not a new dependency. The host must advertise
what it can actually render through `SwayveHostInfo.supportedEmbeds`, and must
not claim an embed kind it cannot drive.

The single assignment site (`app/app.dart:265`) is a genuine advantage: there is
exactly one place where the seam is wired, so widening it is a contained change
rather than a search-and-replace. The host must keep it that way — one
assignment, resolved through `registry.providers<SwayveStreamProvider>()`, with
no per-plugin branching at the call site.

One existing behaviour must be preserved and is worth citing as the model for
the rest: `PlayerController._canPlay` (`:660`) already **drops unresolvable
tracks from the queue rather than stalling**. That is exactly the failure
isolation this specification asks for elsewhere. A plugin whose
`resolvePlayback` throws or times out must cause its track to be skipped, not
the queue to hang.

---

## 6 · Rendering

The host must render plugin data with the widgets it already has. Plugins supply
data; the host supplies experience. These take plain models and therefore accept
mapped plugin data unchanged:

| Widget | Location |
|---|---|
| `MusicTrackRow` | `lib/design/components/music_track_row.dart:37` |
| `AlbumTile` / `ArtistTile` / `MediaShelf` | `lib/design/components/media_tiles.dart:14`, `:145`, `:257` |
| `SectionHeader` / `UtilityLabel` | `lib/design/components/utility_label.dart:92`, `:23` |
| `MusicArtwork` | `lib/design/components/music_artwork.dart:25` |
| `StatusLabel` | `lib/design/components/status_label.dart:33` |

All are exported from the single barrel `lib/design/design.dart`.

`StatusLabel` is the component the host must use for the *"— Temporarily
unavailable"* state of a `degraded` plugin.

The host must not add a plugin-specific widget, a plugin-specific theme hook, or
a way for a plugin to influence rendering. There is no widget surface in the SDK
and none is planned; see
[architecture.md](architecture.md#why-the-sdk-is-pure-dart-with-no-flutter-dependency)
for why the client's use of `package:material_ui/material_ui.dart` (bridged by
`MaterialUiCompatibilityBridge` in `lib/app/app.dart`) makes that the right
answer rather than merely a convenient one.

The host must also render the settings page for each plugin from its manifest's
`settings` descriptors, including the `secret` type routing to the credential
store rather than to plugin storage. Plugins never draw their own settings UI.

---

## 7 · Failure isolation and timeouts

**A broken plugin must never break Swayve.** These are obligations on the host,
not requests of the plugin — a plugin cannot be trusted to honour its own
timeout, which is the whole reason the host applies one.

### Timeouts

The host must apply its own hard timeout to every call into a plugin,
independently of anything the plugin declares:

| Phase | Bound |
|---|---|
| `initialize` | `SwayveTimeouts.initialize` — 8s |
| `dispose` | `SwayveTimeouts.dispose` — 3s |
| A single provider operation | `SwayveTimeouts.operation` — 20s |
| A single HTTP request through `SwayveHttpClient` | `SwayveTimeouts.request` — 10s |

A manifest's `timeouts.requestMs` / `timeouts.operationMs` may *lower* these; it
must never raise them past the host's own ceiling. A breach is treated as
`SwayvePluginUnavailableException` — the host does not wait for a plugin that
will not answer, and does not distinguish "slow" from "broken" past the bound.

A plugin that hangs in `dispose` must be abandoned, not awaited.

### Error isolation

Every host→plugin call must be individually guarded. Concretely:

- **No plugin exception may propagate into host code.** Catch at the boundary,
  including `Error` and not only `Exception`, and including from a `Stream` the
  plugin returned.
- **A failing provider degrades its own surface only.** A search fan-out must
  use a per-provider guard so one thrown exception yields one empty bucket, not
  a failed search. `Future.wait` without per-future error handling is
  specifically wrong here — one rejection fails the whole set.
- **Move the plugin to `degraded`**, keep it loaded, stop merging its results,
  and show *"&lt;Plugin name&gt; — Temporarily unavailable"* via `StatusLabel`.
  Do not unload it and do not retry in a tight loop.
- **Never surface a stack trace to the user.** Developer detail goes to the log.
- **Playback follows `_canPlay`'s existing precedent**: an unresolvable track is
  dropped from the queue and playback continues with the next one.
- **Zero plugins is the baseline that must keep working.** Every plugin-aware
  code path must have a correct empty case, and the client must build and run
  with this repository deleted from disk.

### Permission enforcement

The host must construct each plugin's `SwayvePluginContext` from its declared
permissions, and must throw `SwayvePermissionDeniedException` **synchronously**
on access to an undeclared facility — not return a failed future, which a plugin
could swallow. It must restrict `SwayveHttpClient` to the manifest's
`network.hosts`, refusing undeclared hosts at the client rather than at the
network, and must namespace `SwayvePluginStorage` per plugin with no API that
takes a plugin id and no key enumeration. See
[permissions.md](permissions.md#storage-isolation).

---

## Summary of required client work

| Area | Change | Size |
|---|---|---|
| Registry | New: type-keyed provider registry, lifecycle, compatibility checks, permission enforcement | Large — this is the system |
| `LibraryKind` | Add a fourth case (`pluginSource`) and un-hardcode `MobileController.libraries` | Medium |
| `LibraryStore.search` | Make async/streaming; fan out to providers in parallel with per-provider isolation | **Large — touches every caller** |
| Playback seam | Widen `RemoteAudioResolver` to async and to carry headers, expiry, kind, embed, mimeType | Large, but contained to one assignment site |
| Model mapping | Hand-written `SwayveTrack` ⇄ `Track`; decide the `Album`/`Artist` construction path | Medium |
| Availability | Map three independent booleans onto the 3-way enum without conflating them with `LibraryGrant` | Small, easy to get subtly wrong |
| Rendering | Reuse existing components; add the plugin settings page | Small |
| Playlists | Nothing — no host type exists. Ignore playlist results | None |

---

## See also

- [architecture.md](architecture.md) — the boundary this document implements
- [capabilities.md](capabilities.md) — the interfaces the host calls
- [permissions.md](permissions.md) — what the host must enforce
- [testing.md](testing.md#acceptance-checklist) — how the host side is judged
