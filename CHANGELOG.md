# Changelog

All notable changes to this repository are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Plugins under `plugins/` and the SDK under `packages/swayve_plugin_sdk` are
versioned and released independently; see
[docs/publishing.md](docs/publishing.md). This file tracks the repository as a
whole.

## [Unreleased]

### Added

- **`source`, an optional manifest block** — `sourceId`, `displayName`,
  `iconName`, `contentTypes` and `availability`, so a plugin can declare itself
  as a *place a query can be sent* rather than leaving the host to derive that
  from its capability list. Searchability is not repeated here: the existing
  `search` capability remains the only place it is stated. `SwayveContentType`
  and `SwayveSourceAvailability` join the closed vocabularies, and
  `SwayveSourceDescriptor` carries the same shape at runtime so a plugin can
  republish a live availability. Every field is optional and the whole block is
  optional; a manifest that omits it validates exactly as before.
- **`SwayveTrack.alternateNames`** — original, romanized and translated titles
  for a track, its credit and its release, plus free-form aliases, as
  `SwayveAlternateNames`. A name the service itself published is the best answer
  anyone downstream will ever have, and several services already hold these in
  payloads the plugins were discarding. Optional, defaulting to
  `SwayveAlternateNames.none`, so a provider that publishes none is unaffected.
- **`session_capture` capability** — a thirteenth entry in the closed
  capability vocabulary, and `SwayveSessionCaptureController` in
  `swayve_plugin_sdk`, for a plugin whose sign-in has no redirect URL to hand
  back — only page state the host must extract itself. Unlike `webview` and
  `authentication`, which each require one permission, `session_capture` is
  the first capability requiring **two**: `webview` (the capture flow is a web
  view presentation) and `external_auth` (it ends by writing straight into the
  credential store). `SwayvePermissionEnforcement.guardAll` generalises the
  existing single-permission `guard` to check a facility gated on more than
  one permission, throwing on the first missing one. The manifest's new
  `session_capture` block (`hosts` plus a `capture` list) draws `from` from a
  closed, host-owned vocabulary — `cookie_header` and
  `page_script:youtube_page_id` — so a plugin names *what* to capture, never
  *how*; a new rule 12 validates the block is well-formed and that every
  `as_secret` names a declared `secret` setting. Bumps `schemaVersion` to 4;
  existing `schemaVersion: 1`–`3` manifests keep validating unchanged.
- **`personal_library_push` capability** — a fourteenth entry in the closed
  capability vocabulary, and `SwayveLibraryPushProvider` in
  `swayve_plugin_sdk`, for a plugin that pushes tracks from the local Swayve
  library up to its own service. This is the write counterpart of
  `personal_library`, and it is its own capability rather than a method
  bolted onto `SwayveLibraryProvider` because write access is a materially
  bigger trust grant than read access and deserves its own visible manifest
  line — the same reasoning `docs/capabilities.md` already gives for why
  `playlist_read` never grew a `_write` sibling. It structurally requires
  `personal_library` (rule 1c, alongside `personal_library`'s own existing
  requirement of `authentication`) and needs no new permission: `network`,
  already implied by `personal_library`, is the whole mechanism. The
  interface has no progress callback — every provider call in this SDK is a
  bounded `Future`, and a whole push's progress is file-granular and
  byte-weighted across files, which is a host concern, not this interface's.
  `SwayveHttpClient` grows `postMultipart`, a single-file, buffered
  `multipart/form-data` POST, plus the `SwayveMultipartFile` it takes,
  implemented on `FakeSwayveHttpClient` for plugin tests. New models
  `SwayveUploadItem`, `SwayveUploadOutcome` and `SwayveUploadResult`, and a
  new `SwayveUploadHashAlgorithm` enum (`md5` for now) so a provider can
  declare which digest a host should compute for dedup, or `null` when it
  has no dedup concept at all. `FakeSwayvePluginContext` grows
  `registerLibraryPushProvider`/`libraryPushProviders`, mirroring
  `registerLibraryProvider` exactly. See
  `docs/proposals/library-push.md` for the full design record. Bumps
  `schemaVersion` to 5; existing `schemaVersion: 1`–`4` manifests keep
  validating unchanged.

### Fixed

- **`validate_plugin --all` no longer fails on a repository with no plugins.**
  The plugin catalogue moved to its own repository, leaving `--all` over the
  default root a hard usage failure on every push and `validate` red on `main`
  for a reason unrelated to any change under review. Nothing to validate is now
  a passing answer; an explicitly named `--plugins-root` that holds nothing is
  still a usage error, because somebody who named a directory meant it to exist.

- **`artist_activity` capability** — an eleventh entry in the closed capability
  vocabulary, and `SwayveArtistActivityProvider` in `swayve_plugin_sdk`, for a
  plugin to expose an artist's own public activity on the provider's service
  (their liked and reposted tracks). Bumps `schemaVersion` to 2; existing
  `schemaVersion: 1` manifests keep validating unchanged.

- **`personal_library` capability** — a twelfth entry in the closed capability
  vocabulary, and `SwayveLibraryProvider` in `swayve_plugin_sdk`, for a plugin
  to expose *the signed-in user's own* liked tracks. Unlike `artist_activity`,
  it takes no target id at all — there is no artist to name, because the
  account is the plugin's own session. A new cross-field rule
  (`capability_requires_capability`) requires `authentication` alongside it:
  there is no "own" library without a session. Bumps `schemaVersion` to 3;
  existing `schemaVersion: 1` and `2` manifests keep validating unchanged.

## [0.1.0] — 2026-08-15

Initial foundation: the plugin contract, the SDK that expresses it, the tooling
that enforces it, and two reference plugins. Pre-1.0 — every interface here may
change.

### Added

- **`packages/swayve_plugin_sdk`** — the public SDK. Pure Dart with zero runtime
  dependencies beyond `package:meta`: no Flutter, no `dart:io`, no `dart:ui`.
  - `SwayvePlugin`, `SwayvePluginFactory`, `SwayvePluginIdentity`, and
    `SwayvePluginContext` as the single surface a plugin may touch.
  - Nine provider interfaces, one per capability that has one:
    `SwayveSearchProvider`, `SwayveCatalogProvider`, `SwayveStreamProvider`,
    `SwayveMetadataProvider`, `SwayveLyricsProvider`, `SwayveScrobbleProvider`,
    `SwayveArtworkProvider`, `SwayvePlaylistProvider`, `SwayveAuthProvider`.
  - Normalized models — `SwayveMediaId`, `SwayveTrack`, `SwayveAlbum`,
    `SwayveArtist`, `SwayvePlaylist`, `SwayveAvailability`, `SwayveImageRef`,
    `SwayveSearchQuery` / `SwayveSearchResult`, `SwayvePage`, `SwayveLyrics`,
    `SwayveScrobble` — immutable, value-equal, with hand-written
    `toJson`/`fromJson` and no code generation.
  - `SwayvePlayableSource` with `directUrl`, `hlsUrl`, `dashUrl`, `localFile`
    and `webEmbed` kinds, carrying headers, expiry and availability.
  - Host facilities: `SwayveHttpClient`, `SwayvePluginStorage`,
    `SwayveCredentialStore`, `SwayveSettingsView`, `SwayvePluginLogger`,
    `SwayveWebViewController`.
  - A sealed `SwayvePluginException` hierarchy, `SwayveCancellationToken`, and
    `SwayveTimeouts`.
  - A reference permission-enforcement mixin shared by the host and the test
    harness, so the two cannot drift apart.
- **`packages/swayve_plugin_sdk/testing.dart`** — `FakeSwayvePluginContext`
  (which enforces the declared permission set), `FakeSwayveHttpClient` (canned
  responses, recorded requests, induced throws and hangs),
  `InMemorySwayvePluginStorage`, `InMemorySwayveCredentialStore`,
  `RecordingSwayvePluginLogger`, `SwayveCancellationTokenSource`.
- **`schema/swayve-plugin.schema.json`** — JSON Schema (draft 2020-12) for
  `plugin.json` at `schemaVersion` 1, with `additionalProperties: false` at
  every level.
- **Capability vocabulary (10, closed):** `search`, `catalog`, `streaming`,
  `metadata`, `lyrics`, `scrobbling`, `authentication`, `webview`, `artwork`,
  `playlist_read`.
- **Permission vocabulary (5, closed):** `network`, `webview`, `external_auth`,
  `local_plugin_storage`, `clipboard`.
- **`tools/validate_plugin.dart`** — schema validation plus ten cross-field
  rules, each with a stable diagnostic code, human and `--json` output, and
  `--all`, `--strict`, `--quiet` and `--help` flags.
- **`tools/package_plugin.dart`** — builds a deterministic `.swayveplugin`
  archive with `integrity.json` and `signature.json`, plus a `.sha256` sidecar.
  Validates first and refuses to package a failing manifest. Optional Ed25519
  signing via `--key`.
- **`tools/verify_package.dart`** — recomputes per-file hashes and the canonical
  bundle digest, enforces the extraction-safety rules, and verifies a signature
  against an explicitly supplied `--pubkey`.
- **`plugins/example`** — teaching-grade reference plugin. Implements search and
  catalog against an in-repo fixture with no network access.
- **`plugins/youtube_music`** — reference integration at `0.1.0`, declaring
  `search`, `catalog`, `streaming` and `artwork`; `runtime: compiled`.
- **Documentation** — `docs/architecture.md`, `plugin-manifest.md`,
  `permissions.md`, `capabilities.md`, `packaging.md`, `platforms.md`,
  `development.md`, `testing.md`, `publishing.md`, `versioning.md` and
  `host-integration.md`, plus `README.md`, `CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, `LICENSE` and `NOTICE`.
- **CI** — `validate` and `test` workflows on every push and pull request, and a
  `release` workflow that builds, verifies and publishes plugin artefacts on a
  `<entrypoint>-v<semver>` tag.

### Decided

Choices recorded here because they constrain everything that follows:

- **The SDK is pure Dart with no Flutter dependency.** The Swayve client uses
  `package:material_ui/material_ui.dart` rather than SDK Material, so a
  widget-shaped SDK would force a bad choice between two wrong UI vocabularies.
  Plugins supply data; the host renders UI.
- **Capabilities and permissions are separate vocabularies**, with capabilities
  implying permissions and the validator enforcing the implication.
- **One provider interface per capability**, never one large interface, so the
  registry is the capability index.
- **`runtime: bundled` carries declarative data only**, and `bundled` + `ios` is
  a hard validator error. Swayve cannot download and execute arbitrary code on
  iOS and does not pretend otherwise.
- **Encryption is not the security model.** Integrity (hashes), identity
  (signatures) and explicit permissions are.
- **Streamable, downloadable and on-device are three independent facts**, never
  derived from one another.
- **No code generation anywhere**, matching the client, which has none.
- **The SDK is consumed as a git dependency**, never a relative path, so the
  client never depends on this repository existing on disk and a plugin resolves
  identically from any checkout.

### Not implemented in this release

Stated so nobody plans against a promise:

- **The Swayve client has no plugin system.** No loader, no registry, no
  extension points. `docs/host-integration.md` is a specification of the work
  the client must still do, written against a survey of the real client code —
  not a description of an existing system.
- **`playlist_read` has no host consumer.** The client has no `Playlist` type at
  all; the capability exists so the interface is stable before the feature
  lands.
- **No plugin registry or discovery index.** `registry.json` is future work;
  GitHub Releases is the distribution channel.
- **No key distribution, trust store or revocation.** Signing is implemented;
  deciding which keys are trusted is not answered.
- **No secure at-rest backing for the credential store**, no token refresh
  scheduling, and no credential encryption — the interfaces are specified, the
  host implementation does not exist.
- **No in-app installation, no automatic updates, no debug local-directory
  loader.** The working development path is the test harness plus
  `runtime: compiled` plugins whose source lives in this repository.

Release tags in this repository are per-component
(`<entrypoint>-v<semver>`, `sdk-v<semver>`), so there is no repository-wide
`v0.1.0` tag to link to. `0.1.0` above describes the foundation as a whole.

[Unreleased]: https://github.com/dazacode/swayve-plugins/commits/main
[0.1.0]: https://github.com/dazacode/swayve-plugins/releases
