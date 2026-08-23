/// Rules that apply to every provider interface in this SDK.
///
/// There is one interface per capability, never one large interface: a plugin
/// implements exactly the surfaces it declared, and the host discovers what a
/// plugin can do by which providers it registered rather than by asking it.
///
/// Every method on every provider must, within `SwayveTimeouts.operation`,
/// either complete, throw a `SwayvePluginException`, or honour cancellation.
/// The host applies its own hard deadline regardless and treats a breach as
/// `SwayvePluginUnavailableException` (principle 7).
///
/// Conventions the host relies on:
/// * "not found" is an empty result or `null`, never an exception;
/// * "I cannot do this at all" is `SwayvePluginUnsupportedException`;
/// * "I could not do it right now" is `SwayvePluginUnavailableException`;
/// * a `cancel` token, when passed, is checked before expensive work and
///   after every await.
library;

import 'cancellation.dart';
import 'enums.dart';
import 'models/album.dart';
import 'models/artist.dart';
import 'models/auth_state.dart';
import 'models/browse.dart';
import 'models/image_ref.dart';
import 'models/lyrics.dart';
import 'models/media_id.dart';
import 'models/playlist.dart';
import 'models/scrobble.dart';
import 'models/search.dart';
import 'models/track.dart';
import 'models/upload.dart';
import 'playback.dart';

/// Free-text search. Capability: `search`.
abstract interface class SwayveSearchProvider {
  /// Searches the provider for [query].
  ///
  /// Returns a result even when nothing matched — an empty result and a
  /// failure are different facts, and the host shows them differently.
  /// Honour `query.kinds` and treat `query.limit` as a per-kind ceiling.
  Future<SwayveSearchResult> search(
    SwayveSearchQuery query, {
    SwayveCancellationToken? cancel,
  });
}

/// Browsing a provider's catalogue. Capability: `catalog`.
abstract interface class SwayveCatalogProvider {
  /// Returns a page of albums.
  Future<SwayvePage<SwayveAlbum>> albums(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });

  /// Returns a page of artists.
  Future<SwayvePage<SwayveArtist>> artists(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });

  /// Returns a page of tracks.
  Future<SwayvePage<SwayveTrack>> tracks(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });

  /// Returns the album [id] identifies, or `null` if it no longer exists.
  ///
  /// An id this provider did not mint is `null`, not an error.
  Future<SwayveAlbum?> album(
    SwayveMediaId id, {
    SwayveCancellationToken? cancel,
  });

  /// Returns the artist [id] identifies, or `null` if it no longer exists.
  Future<SwayveArtist?> artist(
    SwayveMediaId id, {
    SwayveCancellationToken? cancel,
  });
}

/// Turning a media id into something the host can play. Capability:
/// `streaming`.
abstract interface class SwayveStreamProvider {
  /// Resolves [id] to a playable source.
  ///
  /// Called immediately before playback and again whenever a previous
  /// source's `expiresIn` elapses, so it must be cheap enough to sit on the
  /// play path. Throw `SwayvePluginAuthRequiredException` when the user must
  /// sign in first, and `SwayvePluginUnsupportedException` when this item
  /// cannot be played at all under the given [hints].
  Future<SwayvePlayableSource> resolvePlayback(
    SwayveMediaId id, {
    SwayvePlaybackHints hints = SwayvePlaybackHints.defaults,
    SwayveCancellationToken? cancel,
  });
}

/// Filling in details for a track the host already has. Capability:
/// `metadata`.
abstract interface class SwayveMetadataProvider {
  /// Returns an enriched copy of [track], or `null` when this provider has
  /// nothing to add.
  ///
  /// The implementer must return a *copy* with fields filled in, must keep
  /// `track.id` unchanged, and must not overwrite a field the host already
  /// populated with a worse value. Enrichment is additive.
  Future<SwayveTrack?> enrichTrack(
    SwayveTrack track, {
    SwayveCancellationToken? cancel,
  });
}

/// Lyrics for a track. Capability: `lyrics`.
abstract interface class SwayveLyricsProvider {
  /// Returns lyrics for [id], or `null` when none were found.
  Future<SwayveLyrics?> lyrics(
    SwayveMediaId id, {
    SwayveCancellationToken? cancel,
  });
}

/// Reporting plays to an external service. Capability: `scrobbling`.
///
/// Both methods are fire-and-forget from the host's perspective: it awaits
/// them so failures are attributable, but a failure never interrupts
/// playback. Providers should queue and retry internally rather than
/// throwing on a transient network error.
abstract interface class SwayveScrobbleProvider {
  /// Reports that playback of [scrobble] has just started.
  Future<void> nowPlaying(SwayveScrobble scrobble);

  /// Reports a completed play.
  ///
  /// The host decides when a play "counts" and calls this once per play. A
  /// provider must be idempotent enough that a repeated call for the same
  /// `id` and `playedAt` does not double-count.
  Future<void> scrobble(SwayveScrobble scrobble);
}

/// Cover art and images. Capability: `artwork`.
abstract interface class SwayveArtworkProvider {
  /// Returns artwork for [id] at approximately [size], or `null` when the
  /// provider has none.
  ///
  /// [size] is an intent, not a guarantee: return the closest asset and
  /// report its real dimensions on the returned reference.
  Future<SwayveImageRef?> artwork(
    SwayveMediaId id, {
    SwayveArtworkSize size = SwayveArtworkSize.medium,
    SwayveCancellationToken? cancel,
  });
}

/// Read-only playlist browsing. Capability: `playlistRead`.
abstract interface class SwayvePlaylistProvider {
  /// Returns a page of the playlists this provider exposes.
  Future<SwayvePage<SwayvePlaylist>> playlists(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });

  /// Returns a page of the tracks in playlist [id], in playlist order.
  Future<SwayvePage<SwayveTrack>> playlistTracks(
    SwayveMediaId id,
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });
}

/// An artist's own public activity on the provider's service. Capability:
/// `artistActivity`.
///
/// Both methods take the *artist's* media id, not a track's or a playlist's —
/// this describes what somebody did, not a release they published. Most
/// providers have no concept of this at all and register nothing; a provider
/// that does register one is declaring that a specific artist's likes and
/// reposts are public and worth surfacing next to their catalogue.
abstract interface class SwayveArtistActivityProvider {
  /// Returns a page of tracks [artistId] has liked, most recent first.
  Future<SwayvePage<SwayveTrack>> likedTracks(
    SwayveMediaId artistId,
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });

  /// Returns a page of tracks [artistId] has reposted, most recent first.
  Future<SwayvePage<SwayveTrack>> repostedTracks(
    SwayveMediaId artistId,
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });
}

/// The signed-in user's own liked tracks on the provider's service.
/// Capability: `personal_library`.
///
/// This is not [SwayveArtistActivityProvider]. That interface takes an
/// *artist's* media id and describes somebody else's public activity; this one
/// takes no target id at all, because there is nothing to name — the plugin's
/// own session *is* the account whose library this returns. A provider that
/// registers this is declaring "I can turn my signed-in session into a
/// library the host can browse", which only makes sense for a plugin that also
/// declares `authentication`: without a session there is no "own" to speak of.
///
/// Most providers have nothing here, the same way most have nothing for
/// [SwayveArtistActivityProvider] — a plugin serving a bundled or anonymous
/// catalogue has no personal library to expose, and registering this provider
/// without ever being signed in would just be catalog browsing wearing a
/// different name.
abstract interface class SwayveLibraryProvider {
  /// Returns a page of tracks the signed-in user has liked, most recent
  /// first.
  ///
  /// Called only while the plugin reports `SwayveAuthStatus.signedIn`; a call
  /// made while signed out should throw
  /// `SwayvePluginAuthRequiredException` rather than return an empty page,
  /// so the host can tell "nothing liked yet" apart from "not signed in".
  Future<SwayvePage<SwayveTrack>> likedTracks(
    SwayveBrowseRequest request, {
    SwayveCancellationToken? cancel,
  });
}

/// Pushing tracks from the local Swayve library up to the provider's own
/// service. Capability: `personal_library_push`.
///
/// The host, not the plugin, owns the local-file loop: no plugin can read
/// the device filesystem, so the host reads each track's bytes itself and
/// hands them over one call at a time through [uploadTrack]. That is also
/// why this interface has no progress callback anywhere on it. Every
/// provider method in this SDK is a bounded, timeout-checked `Future`
/// (principle 7) — a broken plugin must never be able to hang the host the
/// way a raw byte stream could — and a whole push is many such calls, not
/// one long-running one. Progress across the whole run is therefore the
/// host's concern, not this interface's: it is file-granular and
/// byte-weighted across whichever files the host is currently looping
/// through, computed the same way the host already computes progress for
/// its other many-files, one-at-a-time operations.
///
/// [dedupAlgorithm] and [knownUploadHashes] exist so the host can skip a
/// track the provider's service already has before spending any bandwidth
/// resending it. [dedupAlgorithm] is nullable because not every provider's
/// upload protocol has a dedup concept at all — a provider returning `null`
/// is declaring "every push is a fresh upload; there is nothing here to
/// check first," and the host must not call [knownUploadHashes] in that
/// case.
abstract interface class SwayveLibraryPushProvider {
  /// The digest the host must compute over a candidate track's bytes to
  /// compare against [knownUploadHashes], or `null` when this provider has
  /// no dedup concept to offer.
  SwayveUploadHashAlgorithm? get dedupAlgorithm;

  /// Returns every hash, in [dedupAlgorithm]'s form, the provider's service
  /// already holds for this signed-in account.
  ///
  /// Only ever called when [dedupAlgorithm] is non-null. The host computes
  /// the same digest over each local candidate and treats a match as
  /// [SwayveUploadOutcome.alreadyPresent] without calling [uploadTrack] —
  /// unless the user has explicitly chosen to push a known duplicate anyway,
  /// in which case the host calls [uploadTrack] regardless and leaves it to
  /// the provider's own service to decide what a duplicate upload means.
  Future<Set<String>> knownUploadHashes({SwayveCancellationToken? cancel});

  /// Uploads one track's bytes.
  ///
  /// Called once per track, in a host-driven loop — never handed a batch,
  /// and never expected to report on more than the one [item] it was given.
  /// A single track failing to upload is reported through
  /// [SwayveUploadResult.outcome] being [SwayveUploadOutcome.failed], not by
  /// throwing: the host keeps looping through the remaining tracks
  /// regardless and shows every failure together at the end of the run,
  /// which only works if one bad file cannot unwind the whole call stack.
  /// Reserve throwing for what the other conventions in this file already
  /// reserve it for — the plugin cannot do this at all, or could not do it
  /// right now — not for an ordinary per-track rejection from the remote
  /// service.
  Future<SwayveUploadResult> uploadTrack(
    SwayveUploadItem item, {
    SwayveCancellationToken? cancel,
  });
}

/// A user-facing sign-in flow. Capability: `authentication`, permission
/// `external_auth`.
///
/// The plugin owns its credentials end to end: it obtains them, stores them
/// in its own credential slot, and refreshes them. The host only learns the
/// state, so that it can render a sign-in affordance and an account row.
abstract interface class SwayveAuthProvider {
  /// Emits whenever the authentication state changes.
  ///
  /// Must be a broadcast stream: the host may listen more than once, and it
  /// may start listening long after `initialize`. It should emit the current
  /// state to a new listener where the implementation can manage it.
  Stream<SwayveAuthState> get authStateChanges;

  /// Returns the current state, without prompting the user.
  ///
  /// Safe to call at any time, including during startup. Must not open a web
  /// view or make the user wait on the network longer than necessary.
  Future<SwayveAuthState> authState();

  /// Starts an interactive sign-in and completes when it settles.
  ///
  /// Only ever called in response to a user action. May present a web view
  /// through `SwayvePluginContext.webView`. Completes with the resulting
  /// state — including a failed one — rather than throwing, except when the
  /// flow could not be started at all.
  Future<SwayveAuthState> authenticate();

  /// Signs out and discards every stored credential for this plugin.
  ///
  /// Must succeed even when the network is unreachable: the user asked to be
  /// signed out, and local credentials must be gone afterwards regardless.
  Future<void> signOut();
}
