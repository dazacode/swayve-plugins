# Capabilities

> Examples below reference `plugins/youtube_music` as a worked case. It now
> lives in
> [`Daza-Swayve-plugins`](https://github.com/dazacode/Daza-Swayve-plugins),
> not in this repository — the reasoning still applies, only the path changed.

A capability is a question the plugin can answer. The vocabulary is closed —
arbitrary strings are rejected by the schema — and each capability corresponds
to one provider interface, registered during `initialize`:

```dart
@override
Future<void> initialize(SwayvePluginContext context) async {
  context.registerSearchProvider(MySearchProvider(context.http));
  context.registerCatalogProvider(MyCatalogProvider(context.http));
}
```

Declaring a capability in the manifest and never registering its provider is a
defect: the host will report the plugin as unavailable rather than silently
treating the capability as absent.

Adding a capability to the vocabulary is a schema change and requires the docs,
the SDK and the validator to move together. There are ten in v1.

## The ten at a glance

| Capability | Provider interface | Registration | Implies |
|---|---|---|---|
| `search` | `SwayveSearchProvider` | `registerSearchProvider` | `network` |
| `catalog` | `SwayveCatalogProvider` | `registerCatalogProvider` | `network` |
| `streaming` | `SwayveStreamProvider` | `registerStreamProvider` | `network` |
| `metadata` | `SwayveMetadataProvider` | `registerMetadataProvider` | `network` |
| `lyrics` | `SwayveLyricsProvider` | `registerLyricsProvider` | `network` |
| `scrobbling` | `SwayveScrobbleProvider` | `registerScrobbleProvider` | `network` |
| `artwork` | `SwayveArtworkProvider` | `registerArtworkProvider` | `network` |
| `playlist_read` | `SwayvePlaylistProvider` | `registerPlaylistProvider` | `network` |
| `authentication` | `SwayveAuthProvider` | `registerAuthProvider` | `external_auth` |
| `webview` | *(none — host facility)* | — | `webview` |

`webview` is the one capability with no provider interface. It does not answer a
question; it declares that this plugin's flows require the host to present a web
surface, which the plugin then drives through `SwayveWebViewController`. It is
in the capability vocabulary rather than the permission vocabulary alone because
the host needs to know at *discovery* time whether a plugin will need an embed
surface — on a platform or build where none is available, that is a
compatibility fact, not a runtime surprise.

In the Dart enum the wire names are camel-cased: `SwayveCapability.playlistRead`
has `wireName == 'playlist_read'`. Use `SwayveCapability.fromWire('playlist_read')`
to go the other way.

---

## `search`

```dart
abstract interface class SwayveSearchProvider {
  Future<SwayveSearchResult> search(
    SwayveSearchQuery query, {
    SwayveCancellationToken? cancel,
  });
}
```

```dart
final class SwayveSearchQuery {
  String text;
  Set<SwayveSearchKind> kinds;   // track, album, artist, playlist
  int limit;
  String? cursor;
}

final class SwayveSearchResult {
  final List<SwayveTrack> tracks;
  final List<SwayveAlbum> albums;
  final List<SwayveArtist> artists;
  final List<SwayvePlaylist> playlists;
  final String? cursor;
  final bool partial;   // the provider truncated or degraded its answer
}
```

**What the host does with it.** It fans a single user query out to every
registered `SwayveSearchProvider` in parallel, merges the results into the
Explore search screen, and groups them by source library. It does not know which
provider produced which row — the grouping keys off the library, not the
provider.

`kinds` is a request, not a promise in either direction: honour it where you
can, and return empty lists for kinds you do not support rather than throwing.
Set `partial: true` when you returned something usable but incomplete — a
degraded upstream, a truncated page — so the host can render the result without
implying it is exhaustive.

Respect `cancel`: the user types, and the previous query is cancelled. A search
provider that ignores cancellation will pile up requests behind every keystroke.

## `catalog`

```dart
abstract interface class SwayveCatalogProvider {
  Future<SwayvePage<SwayveAlbum>>  albums(SwayveBrowseRequest request,  {SwayveCancellationToken? cancel});
  Future<SwayvePage<SwayveArtist>> artists(SwayveBrowseRequest request, {SwayveCancellationToken? cancel});
  Future<SwayvePage<SwayveTrack>>  tracks(SwayveBrowseRequest request,  {SwayveCancellationToken? cancel});
  Future<SwayveAlbum?>  album(SwayveMediaId id,  {SwayveCancellationToken? cancel});
  Future<SwayveArtist?> artist(SwayveMediaId id, {SwayveCancellationToken? cancel});
}
```

**What the host does with it.** This is what makes a plugin *browsable* rather
than merely searchable: the source appears as a library the user can open, with
album, artist and track shelves rendered by the host's existing `MediaShelf`,
`AlbumTile` and `ArtistTile` widgets.

Pagination is cursor-based, never offset-based, because offsets break under
concurrent upstream mutation. Return `SwayvePage(items: [...], cursor: next)`
and `null` for `cursor` when there is no more. `hasMore` is defined purely as
`cursor != null` — a provider that returns a cursor is promising there is
another page, so do not hand back a cursor you know is exhausted.

`album(id)` and `artist(id)` return `null` for "not found" and throw only for
"could not find out". That distinction matters to the host: `null` renders an
empty state, a throw sends the plugin to `degraded`.

## `streaming`

```dart
abstract interface class SwayveStreamProvider {
  Future<SwayvePlayableSource> resolvePlayback(
    SwayveMediaId id, {
    SwayvePlaybackHints hints,
    SwayveCancellationToken? cancel,
  });
}
```

```dart
enum SwayvePlayableKind { directUrl, hlsUrl, dashUrl, localFile, webEmbed }

final class SwayvePlayableSource {
  final SwayvePlayableKind kind;
  final Uri? uri;                          // directUrl / hlsUrl / dashUrl / localFile
  final SwayveWebEmbed? embed;             // webEmbed only
  final Map<String, String> headers;       // request headers the host must send
  final Duration? expiresIn;               // host must re-resolve after this
  final SwayveAvailability availability;   // must agree with the manifest's `media`
  final String? mimeType;
  bool get isWebEmbed;
}
```

There is no public unnamed constructor. Build one through a named constructor,
which is what keeps `uri` and `embed` from ever both being set or both being
absent:

```dart
SwayvePlayableSource.directUrl(uri, headers: …, expiresIn: …, availability: …, mimeType: …)
SwayvePlayableSource.hls(uri, …)
SwayvePlayableSource.dash(uri, …)
SwayvePlayableSource.localFile(uri, availability: …, mimeType: …)
SwayvePlayableSource.webEmbed(embed, expiresIn: …, availability: …)
```

`availability` defaults to `SwayveAvailability.streamOnly` on all of them except
`localFile`, which defaults to `onDevice: true`. `localFile` is for a path the
*host* downloaded on the plugin's behalf — a plugin has no filesystem access of
its own.

**What the host does with it.** It resolves the source immediately before
playback and hands it to the audio pipeline. This is the tightest coupling in
the whole system, and the one the client will have to widen most (see
[host-integration.md](host-integration.md#the-playback-seam)).

Three obligations on the plugin:

- **Resolve late.** Signed URLs expire. Set `expiresIn` and expect to be asked
  again; do not cache a resolved URL past its life.
- **Check `host.supportedEmbeds` before returning `webEmbed`, and throw
  `SwayvePluginUnsupportedException` if you have nothing else.** Handing back an
  embed the host cannot render turns a clear capability mismatch into an
  unexplained stall; throwing lets the host drop the track from the queue and
  move on. `hints.allowWebEmbed == false` is the same case.
- **Agree with the manifest.** A plugin declaring `"streamable": false` cannot
  return a streamable source. The host treats disagreement as a defect —
  `plugins/youtube_music` asserts the manifest, its availability constant and
  every resolved source against each other in three separate tests.

`SwayvePlaybackHints` carries `preferAudioOnly` (default `true` — Swayve is a
music player), `maxBitrateKbps` and `allowWebEmbed` (default `true`). Every
field is a hint except `allowWebEmbed`: when it is `false` the host *cannot*
render an embed, so returning one is a bug rather than an unmet preference.

`SwayveWebEmbed` carries the `controls` the host may drive
(`play`, `pause`, `seek`, `volume`, `positionUpdates`) and an optional
`userAgent`. **A control you omit is one the host must disable**, so
over-claiming is worse than claiming nothing — it produces a button that does
nothing.

## `metadata`

```dart
abstract interface class SwayveMetadataProvider {
  Future<SwayveTrack?> enrichTrack(SwayveTrack track, {SwayveCancellationToken? cancel});
}
```

**What the host does with it.** It offers a track the host already has — often a
local file with poor tags — and takes back a more complete one. This is the only
provider that is *additive to another source's data*: a metadata plugin can
improve tracks it did not produce.

Return `null` when you have nothing to add; returning the input unchanged is
also fine but `null` is clearer. Never fabricate: a wrong year or a wrong album
is worse than a missing one, because the host will store it. Preserve the
incoming `id` — enrichment does not re-identify the track.

## `lyrics`

```dart
abstract interface class SwayveLyricsProvider {
  Future<SwayveLyrics?> lyrics(SwayveMediaId id, {SwayveCancellationToken? cancel});
}

final class SwayveLyrics {
  String? plain;
  List<SwayveLyricLine>? synced;   // SwayveLyricLine { Duration at; String text; }
  String? source;
  bool explicitContent;
}
```

**What the host does with it.** It renders lyrics on the now-playing surface,
scrolling in time when `synced` is present and as a static block when only
`plain` is. Populate both when you have both — a host without a synced view
still needs text, and a host with one still needs a fallback for a failed sync.

`source` is attribution and should name the upstream. `explicitContent` lets the
host respect a content filter it may apply.

## `scrobbling`

```dart
abstract interface class SwayveScrobbleProvider {
  Future<void> nowPlaying(SwayveScrobble scrobble);
  Future<void> scrobble(SwayveScrobble scrobble);
}

final class SwayveScrobble {
  SwayveMediaId id; String title; String artist;
  String? album; Duration? duration; DateTime playedAt;
}
```

**What the host does with it.** It calls `nowPlaying` when playback starts and
`scrobble` when a play is considered complete by the host's own rules. The host
decides what "complete" means; the plugin does not get a play position stream
and must not try to reconstruct one.

Note that `SwayveScrobble.artist` is a single string, unlike `SwayveTrack.artists`
— scrobble endpoints universally take one artist field, and forcing the plugin
to flatten it at the boundary keeps the flattening rule in one place.

Both methods return `Future<void>`. Failure is reported by throwing a
`SwayvePluginException`; a scrobble that cannot be delivered now should throw
`SwayvePluginUnavailableException` rather than silently succeeding. There is no
host-side retry queue in v1 — if you need one, buffer in your own storage.

## `authentication`

```dart
abstract interface class SwayveAuthProvider {
  Stream<SwayveAuthState> get authStateChanges;
  Future<SwayveAuthState> authState();
  Future<SwayveAuthState> authenticate();
  Future<void> signOut();
}

final class SwayveAuthState {
  final SwayveAuthStatus status;   // see below
  final String? accountLabel;      // what the host shows: "alice@example.com"
  final DateTime? expiresAt;
  final String? message;
  bool get isSignedIn;
  static const SwayveAuthState signedOut;
}
```

**What the host does with it.** It renders a sign-in affordance on the plugin's
settings page, calls `authenticate()` when the user taps it, and listens to
`authStateChanges` to keep the UI honest. It also uses the state to explain
empty results: a search returning nothing because the user is signed out should
say so rather than looking broken.

`authenticate()` must only ever run in response to the host calling it — a
plugin does not decide when to ask the user to sign in. Throw
`SwayvePluginAuthRequiredException` from *other* providers when a call needs
credentials the plugin does not have; the host turns that into the prompt.

The corollary is worth stating, because it is easy to get backwards: **a plugin
with no `authentication` capability must never throw
`SwayvePluginAuthRequiredException`.** `plugins/youtube_music` deliberately maps
HTTP 403 to `SwayvePluginUnavailableException`, because a 403 from an anonymous
client is a regional or consent block rather than a lapsed session, and
reporting auth-required would leave the host offering a sign-in button that
leads nowhere.

`signOut()` must clear the plugin's credential slot, not merely forget it in
memory.

## `webview`

No provider interface. Declaring `webview` means "this plugin's flows require
the host to present a web surface", and the plugin drives it through the
context:

```dart
abstract interface class SwayveWebViewController {
  Future<Uri?> presentForResult(Uri start,
      {required bool Function(Uri) isComplete, Duration? timeout});
}
```

**What the host does with it.** Two things: it presents modal web views for
OAuth-style flows, and it knows — before loading the plugin — that this plugin
needs an embed surface, which is a compatibility input. It also advertises what
it can render through `SwayveHostInfo.supportedEmbeds`
(`SwayveWebEmbedKind.iframe`, `SwayveWebEmbedKind.inAppWebView`), which a
streaming plugin must consult before returning a `webEmbed` source.

`presentForResult` returns `null` for cancellation and timeout alike. Treat that
as "the user declined", not as an error to retry.

## `artwork`

```dart
abstract interface class SwayveArtworkProvider {
  Future<SwayveImageRef?> artwork(
    SwayveMediaId id, {
    SwayveArtworkSize size,
    SwayveCancellationToken? cancel,
  });
}

final class SwayveImageRef { Uri uri; int? width; int? height; String? blurHash; }
enum SwayveArtworkSize { thumbnail, medium, large, original }
```

**What the host does with it.** It fetches and caches the image behind
`MusicArtwork`, at the size the current surface needs — `thumbnail` for a list
row, `large` for now-playing. Returning a 3000px original for a 40px row wastes
the user's data on every scroll, so honour `size` where the upstream offers
choices, and report actual `width`/`height` so the host can lay out before the
bytes arrive.

`blurHash` is optional and worth providing: it is what the host shows in the
gap between layout and load.

Return `null` for "no artwork", not a placeholder URL. The host has a better
placeholder than you do.

## `playlist_read`

```dart
abstract interface class SwayvePlaylistProvider {
  Future<SwayvePage<SwayvePlaylist>> playlists(
      SwayveBrowseRequest request, {SwayveCancellationToken? cancel});
  Future<SwayvePage<SwayveTrack>> playlistTracks(
      SwayveMediaId id, SwayveBrowseRequest request, {SwayveCancellationToken? cancel});
}
```

**What the host does with it: nothing, today.**

This is the one capability with **no host consumer**. The Swayve client has no
`Playlist` type at all — no class, no table, no route, no screen — so there is
nothing for `SwayvePlaylist` to map onto and nowhere for these results to be
rendered. `playlist_read` exists in the vocabulary so that the interface is
stable before the host feature lands, and so that plugins written against a
service with playlists do not have to be redesigned later.

If you implement it today, implement it correctly and test it against
`FakeSwayvePluginContext` — but do not expect a user to see the results, and do
not build a plugin whose value depends on it. `SwayveSearchResult.playlists` has
the same status.

Read-only by name and by design: there is no `playlist_write`, and creating or
editing playlists in a third-party service is not on the v1 surface.

---

## Models these interfaces share

All models are immutable, `const`-friendly, have value equality and hand-written
`toJson`/`fromJson` (no code generation anywhere — the client has none, and the
SDK matches it).

```dart
/// Globally unique across all sources. The host NEVER parses `value`.
final class SwayveMediaId {
  final String pluginId;
  final String value;        // provider-native, opaque to the host
  String get uri;            // "swayve://<pluginId>/<percent-encoded value>"
  static SwayveMediaId parse(String uri);      // throws on a bad uri
  static SwayveMediaId? tryParse(String uri);  // null on a bad uri
}
```

`SwayveMediaId.value` being opaque is load-bearing. It is what lets a plugin use
a numeric id, a URL, a base64 blob or a composite key without the host ever
needing to care — and it is what stops the host from growing provider-specific
parsing.

```dart
/// Three INDEPENDENT facts. Never derive one from another.
final class SwayveAvailability {
  final bool streamable;
  final bool downloadable;
  final bool onDevice;
}
```

`SwayveTrack.artists` is a `List<SwayveArtistRef>`, never a bare `String` —
flattening to a display string is the host's job at the rendering boundary, and
doing it in the plugin destroys information the host may want (per-artist
navigation, for one). The single exception is `SwayveScrobble.artist`, for the
reason given above.

`extra` on every model is a `Map<String, Object?>` the host never interprets.
Use it for provider-specific data you need on the way back in — not as a way to
smuggle instructions to the host, which will ignore them.

---

## See also

- [permissions.md](permissions.md) — what each capability commits you to touching
- [plugin-manifest.md](plugin-manifest.md) — how capabilities are declared and validated
- [host-integration.md](host-integration.md) — what the client must build to consume these
- [testing.md](testing.md) — exercising a provider without a host
