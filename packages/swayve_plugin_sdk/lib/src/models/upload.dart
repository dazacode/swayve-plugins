import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../internal/equality.dart';

/// One local track's bytes and metadata, ready to hand to
/// `SwayveLibraryPushProvider.uploadTrack`.
///
/// The host builds this, never the plugin. No plugin can read the device
/// filesystem — there is no permission that grants it, and there never has
/// been one — so the host is the only side of this call that could ever have
/// read [bytes] off disk in the first place; `SwayveLibraryPushProvider`
/// exists to let the plugin do something with bytes the host is handing it,
/// not to let it go looking for its own.
@immutable
final class SwayveUploadItem {
  /// Creates an upload item.
  const SwayveUploadItem({
    required this.bytes,
    required this.fileName,
    required this.contentHash,
    required this.title,
    required this.artist,
    this.mimeType,
    this.album,
    this.knownDuplicate = false,
  });

  /// The track's raw audio bytes, already read off disk.
  final Uint8List bytes;

  /// The local file's own name. Not necessarily what the remote service
  /// ends up storing the upload under.
  final String fileName;

  /// The MIME type of [bytes], when the host was able to determine one.
  final String? mimeType;

  /// [bytes] digested with whatever
  /// `SwayveLibraryPushProvider.dedupAlgorithm` named, or an empty string
  /// when that getter was `null` and no digest was ever computed.
  final String contentHash;

  /// The track title, exactly as the host's own library holds it.
  final String title;

  /// The track's artist, already flattened to a single string for display —
  /// the same convention `SwayveScrobble.artist` uses, and for the same
  /// reason: the upload protocol behind this feeds one artist field, not a
  /// list.
  final String artist;

  /// The album title, when known.
  final String? album;

  /// Whether [contentHash] matched an entry
  /// `SwayveLibraryPushProvider.knownUploadHashes` returned.
  ///
  /// The host decides this before ever calling `uploadTrack`, so a provider
  /// does not need to recompute or re-check the hash itself to know it. It
  /// does not mean `uploadTrack` will not be called for this item — the host
  /// may still call it after an explicit "push anyway" choice over an
  /// already-known duplicate.
  final bool knownDuplicate;

  @override
  String toString() => 'SwayveUploadItem($fileName, $title by $artist)';

  @override
  bool operator ==(Object other) =>
      other is SwayveUploadItem &&
      fileName == other.fileName &&
      mimeType == other.mimeType &&
      contentHash == other.contentHash &&
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      knownDuplicate == other.knownDuplicate &&
      deepEquals(bytes, other.bytes);

  @override
  int get hashCode => Object.hash(
        fileName,
        mimeType,
        contentHash,
        title,
        artist,
        album,
        knownDuplicate,
        // Hashing every byte of a multi-megabyte audio file on every
        // hashCode call would be wasteful, and contentHash already carries
        // the identity bytes exists to distinguish; length is enough to keep
        // this consistent with == without that cost.
        bytes.length,
      );
}

/// How one `SwayveLibraryPushProvider.uploadTrack` call concluded.
enum SwayveUploadOutcome {
  /// The track was sent and the provider's service accepted it as new.
  uploaded,

  /// The provider's service already had this track: nothing new was stored,
  /// whether because the host skipped the call after a
  /// [SwayveUploadItem.knownDuplicate] match or because the service itself
  /// reported the resend as a no-op.
  ///
  /// Its wire name is `already_present`.
  alreadyPresent,

  /// This one track could not be uploaded.
  ///
  /// Reported as an outcome rather than a thrown exception on purpose: one
  /// track failing must not stop the host's push from moving on to the next
  /// one, and returning a value the host can collect and show at the end of
  /// the run is what keeps that decision out of a try/catch at every call
  /// site. See `SwayveLibraryPushProvider.uploadTrack`.
  failed;

  /// The wire spelling of this outcome.
  String get wireName => switch (this) {
        SwayveUploadOutcome.uploaded => 'uploaded',
        SwayveUploadOutcome.alreadyPresent => 'already_present',
        SwayveUploadOutcome.failed => 'failed',
      };

  /// The outcome named [wire], or `null` if unknown.
  static SwayveUploadOutcome? fromWire(String wire) {
    for (final value in SwayveUploadOutcome.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// What one `SwayveLibraryPushProvider.uploadTrack` call returned.
@immutable
final class SwayveUploadResult {
  /// Creates an upload result.
  const SwayveUploadResult({
    required this.outcome,
    this.remoteId,
    this.message,
  });

  /// How the call concluded.
  final SwayveUploadOutcome outcome;

  /// The provider's own identifier for the uploaded (or already-present)
  /// track, when it has one to give back. The host treats this as opaque.
  final String? remoteId;

  /// A short, developer-facing explanation.
  ///
  /// Worth setting whenever [outcome] is [SwayveUploadOutcome.failed], so
  /// the host's end-of-run failure list can say more than "failed" for a
  /// given file.
  final String? message;

  @override
  String toString() => 'SwayveUploadResult(${outcome.name}, $remoteId)';

  @override
  bool operator ==(Object other) =>
      other is SwayveUploadResult &&
      outcome == other.outcome &&
      remoteId == other.remoteId &&
      message == other.message;

  @override
  int get hashCode => Object.hash(outcome, remoteId, message);
}
