# Changelog

All notable changes to `swayve_plugin_sdk` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is `0.x` the API is unstable: a minor bump may break you.

## 0.1.0

Initial release. Plugin API level 1, manifest schema version 1.

### Added

- `SwayvePlugin`, `SwayvePluginIdentity` and `SwayvePluginFactory` — the entry
  point a compiled plugin exposes.
- `SwayvePluginContext` — the only surface a plugin may touch, with
  permission-guarded access to storage, HTTP, credentials and web views.
- Nine provider interfaces, one per capability: search, catalog, streaming,
  metadata, lyrics, scrobbling, artwork, playlists and authentication.
- Normalized models: `SwayveMediaId`, `SwayveTrack`, `SwayveAlbum`,
  `SwayveArtist`, `SwayvePlaylist`, `SwayveArtistRef`, `SwayveAlbumRef`,
  `SwayveAvailability`, `SwayveImageRef`, `SwayveSearchQuery`,
  `SwayveSearchResult`, `SwayveBrowseRequest`, `SwayvePage`, `SwayveLyrics`,
  `SwayveLyricLine`, `SwayveScrobble` and `SwayveAuthState` — all immutable,
  with value equality and hand-written `toJson`/`fromJson`.
- Playback resolution: `SwayvePlayableSource`, `SwayveWebEmbed` and
  `SwayvePlaybackHints`, so the host can play a plugin's media without
  learning where it came from.
- Host facilities: `SwayveHttpClient`, `SwayveHttpResponse`,
  `SwayvePluginStorage`, `SwayveCredentialStore`, `SwayveSettingsView`,
  `SwayvePluginLogger` and `SwayveWebViewController`.
- A sealed `SwayvePluginException` hierarchy, `SwayveCancellationToken` and
  `SwayveTimeouts`.
- `SwayvePermissionEnforcement`, the reference permission check shared by the
  host and the test harness.
- `Version`, a dependency-free strict SemVer 2.0.0 implementation.
- `package:swayve_plugin_sdk/testing.dart` — `FakeSwayvePluginContext`,
  `FakeSwayveHttpClient`, `FakeSwayveSettingsView`,
  `FakeSwayveWebViewController`, `InMemorySwayvePluginStorage`,
  `InMemorySwayveCredentialStore`, `RecordingSwayvePluginLogger` and
  `SwayveCancellationTokenSource`.
