# Push local library to CloudLocker

Status: **Phase 1 (SDK) implemented — see CHANGELOG.** The
`personal_library_push` capability, `SwayveLibraryPushProvider`,
`SwayveHttpClient.postMultipart` and the models sketched below landed in
`swayve-plugins`; see this repository's `CHANGELOG.md` for the summary and
[capabilities.md](../capabilities.md#personal_library_push) /
[plugin-manifest.md](../plugin-manifest.md#personal_library_push-adds-no-manifest-block)
for the shipped shape. The plugin work (a real `CloudLockerLibraryPushProvider`
in `cloudlocker-swayve-plugin`) and the host work (a push screen in
`personalmusicsync`) are design only below — not yet built. This document is
kept as the design record for all three; the two sketches were updated to
match what actually shipped in the SDK, but the surrounding rationale is
unchanged from the original proposal.

## The problem this solves

The `CloudLocker` plugin, just built, only pulls data **from** CloudLocker —
sign in, browse, stream, artwork, playlists. Every capability in this SDK, in
fact, pulls from a plugin's service; nothing pushes local data **to** one.
The user wants the reverse: push tracks from their local Swayve library up to
their CloudLocker cloud storage, tagged so pushed content is identifiable,
with a choice about what to do with tracks that already exist remotely, and a
real progress indication so a long multi-file operation never looks stuck.

That last requirement is where this stops being "add a method to the
plugin." The SDK has no capability for "push local data to a service" at
all, and no progress-reporting or long-running-operation primitive
anywhere — every provider call today is a bounded `Future` (~20s), matching
the SDK's own design principle that a broken plugin must never hang the
host. This needs a genuine new capability, not a new plugin method bolted
onto an existing one.

## Why not extend `personal_library`

The obvious shortcut is a `uploadTrack` method added straight onto
`SwayveLibraryProvider`, since a plugin that already reads a signed-in
library is exactly the kind of plugin that would also write to one. That is
the wrong shortcut, for the same reason `capabilities.md` already gives for
why `playlist_read` never grew a `_write` sibling: **write access is a
materially bigger trust grant than read access**, and it deserves its own
visible line in the manifest's `capabilities` array rather than living
silently inside a capability the user already granted for a narrower
reason. A user who granted `personal_library` agreed to "let this plugin
read my liked tracks back into Swayve." Silently upgrading that grant to
also mean "and let it send my own files to that service" the day a plugin
author adds one more interface method is exactly the kind of scope creep
this SDK's permission model exists to make visible instead of quiet.

So: a new capability, `personal_library_push`, structurally requiring
`personal_library` be also declared — the same structural mechanism
`personal_library` itself already uses to require `authentication` (rule
1c). No new permission is needed beyond what `personal_library` already
implies: `network`, already covered by the existing permission plus the
manifest's own `network.hosts` allowlist. The trust boundary this proposal
actually needs to add is the capability line itself, not a new permission
mechanism underneath it.

## Proposed shape

A no-plugin-filesystem-access constraint turns out to simplify this a great
deal. No plugin can read the local filesystem — that has never been a
grantable permission in this SDK — so the host must own the local-file loop
and hand bytes to the plugin, which then sends them to its own service. That
means "push" can be modeled as one bounded `Future` call per track, looped
by the host exactly the way the existing intake/phone-sync flows already
work in the client — no new async/streaming plumbing needed in the SDK at
all.

### Interface sketch (shipped)

```dart
abstract interface class SwayveLibraryPushProvider {
  /// The digest the host must compute to compare against
  /// [knownUploadHashes], or null when this provider has no dedup concept.
  SwayveUploadHashAlgorithm? get dedupAlgorithm;

  /// Every hash the provider's service already has on file for this
  /// account, in [dedupAlgorithm]'s form.
  Future<Set<String>> knownUploadHashes({SwayveCancellationToken? cancel});

  /// Uploads one track. Called once per track, in a host-driven loop.
  Future<SwayveUploadResult> uploadTrack(
    SwayveUploadItem item, {
    SwayveCancellationToken? cancel,
  });
}
```

`dedupAlgorithm` and `knownUploadHashes` exist because CloudLocker's own
upload endpoint, hit with just credentials and no file, returns `{md5:
[...]}` — hashes of everything already uploaded. That is genuinely a
provider-specific fact, not something every push target will have, which is
why `dedupAlgorithm` is nullable rather than assumed.

There is no progress callback anywhere on this interface. See
[Explicit non-goals](#explicit-non-goals) for why.

### Manifest sketch

```jsonc
"capabilities": ["search", "catalog", "authentication", "personal_library", "personal_library_push"],
"permissions": ["network", "external_auth"],
"network": { "hosts": ["api.cloudlocker.example", "upload.cloudlocker.example"] }
```

No new manifest block. Unlike `session_capture`, which needed the host to
know in advance which hosts a capture flow would touch and which artifacts
to extract, `personal_library_push` needs nothing from the manifest beyond
the capability declaration itself and `network.hosts`, which already exists.
Whatever a plugin wants to tag pushed content with — a fixed `"Swayve"`
label, in CloudLocker's case — is the plugin's own business, expressed
however it likes on its own side of `uploadTrack`, not something the host
needs to model.

## Threat model notes

This is the first capability in the vocabulary whose entire purpose is
**sending the user's own files somewhere** — every other capability reads
data in, this one sends local files out. That is a different, and in some
ways more consequential, kind of trust than any read capability grants: a
compromised or malicious plugin with `personal_library_push` can exfiltrate
music the user owns to wherever its own service lives, using the same
`network.hosts` allowlist mechanism every other capability already trusts.

The consent copy at grant time should say so explicitly, distinct from
ordinary read-capability copy — "this plugin can upload tracks from your
library to `<service>`" reads very differently from "this plugin can browse
your library on `<service>`," and a host should not reuse the same sentence
for both. This is a host UI concern, not an SDK one, but it is worth
recording here because the capability's very existence is what creates the
need for that distinct copy.

The allowlist enforcement itself is unchanged from every other
`network`-gated capability: a request to a host the manifest did not declare
fails at the client, before it leaves the device, exactly as it does for
every other capability that touches `SwayveHttpClient`.

## Explicit non-goals

- **No generic "any file kind" push.** This is scoped to audio tracks
  specifically — `SwayveUploadItem` carries track metadata (`title`,
  `artist`, `album`), not a generic blob. A future "push arbitrary files"
  facility, if ever needed, is a different and much broader grant than this
  one and is out of scope here.
- **No mid-file byte progress.** `SwayveHttpClient` is buffered, not
  streamed — plugins fetch metadata and short payloads, and now, with
  `postMultipart`, one file per request, but never a chunked upload with
  progress events. Reporting progress *within* a single file's upload would
  mean inventing a new async primitive that does not exist anywhere else in
  this SDK — every provider call is a bounded `Future`, full stop. Progress
  across a whole push is file-granular and byte-weighted across the files
  the host is looping through, computed by the host from its own knowledge
  of how many bytes it has sent so far — a host-side concern, not an SDK
  one, and not something this proposal's SDK surface reports at all.
- **No second plugin gets this yet.** `personal_library_push` is being added
  to the closed vocabulary because CloudLocker's plugin needs it, not because
  a second consumer is queued up. The capability is generic — any plugin
  whose service accepts uploads can declare it — but nothing about this
  phase assumes or builds for a second one.
- **No delete or replace-on-remote semantics.** `uploadTrack` sends a track.
  It has no counterpart for removing a previously pushed track from the
  remote service, and `SwayveUploadOutcome.alreadyPresent` does not imply
  anything about whether a resend replaces what is already there — that is
  entirely between the plugin and its own service. A future "manage what
  I've pushed" facility is out of scope here.
- **No implementation of the plugin or host pieces in this document's own
  scope.** Phase 1 (this repository's SDK) is what the interface above
  actually is; the plugin (`cloudlocker-swayve-plugin`) and host
  (`personalmusicsync`) pieces are separate, later phases, each with its own
  verification before it ships.
