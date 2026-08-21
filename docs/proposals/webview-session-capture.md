# Phase 2: automatic account-context capture

Status: **implemented — see CHANGELOG**. The `session_capture` capability,
`SwayveSessionCaptureController` and the manifest block sketched below landed
in `swayve-plugins`; see this repository's `CHANGELOG.md` for the summary and
`docs/capabilities.md#session_capture` / `docs/plugin-manifest.md#session_capture`
for the shipped shape. This document is kept as the design record — the two
sketches below were updated to match what was actually built (see the
`page_script:youtube_page_id` note in particular), but the surrounding
rationale is unchanged from the original proposal. It exists to record the
shape of the next step after `youtube_music`'s beta ships with manual
credential entry (paste a session cookie, optionally paste a `page_id`) — see
that plugin's `plugin.json` (`session_cookie` and `page_id` settings) and
`lib/src/providers/library_provider.dart` for how they're used today. The
problem generalises past YouTube Music — any plugin whose only sign-in path is
"paste something from DevTools" is a candidate for this — but YouTube Music is
the motivating, worked case below.

## The problem this solves

Today, connecting YouTube Music means: open DevTools on music.youtube.com,
find a `/browse` request, copy the `cookie` header, paste it into Settings.
Multi-channel accounts also need `x-goog-pageid` off the same request — a
second DevTools trip most users won't know to make, and won't know *why*
they'd need to until their liked-songs sync comes back empty for a reason
that looks identical to "not signed in" (see `youtube_music`'s
`looksSignedOut` doc comment in `feed_parser.dart`).

Phase 2's goal: after the user completes an ordinary-looking sign-in inside
the app, the plugin ends up with both values automatically. No DevTools, no
manual paste, no knowing what `x-goog-pageid` even is.

## Why this is not "just use `presentForResult`"

The SDK's existing `webview` permission is deliberately narrow —
`SwayveWebViewController.presentForResult` hands a plugin a completion
*URL* and nothing else:

> "no cookies, no page content, no script injection ... A plugin that needs
> the *contents* of a page must fetch it itself through `SwayveHttpClient`."
> — `packages/swayve_plugin_sdk/lib/src/host/webview.dart`

That's the right default: a plugin asking to read the cookie jar of a
web view is asking for a lot more than "let the user sign in somewhere."
Widening `presentForResult` itself to leak cookies would quietly turn every
existing and future `webview` grant into a cookie-read grant, for every
plugin that ever asks for a sign-in page — far broader than what this
feature actually needs. **This proposal does not touch `presentForResult`.**
It adds a new, separate, more restricted surface instead — and a new
permission gating it.

## Proposed shape: `session_capture`, a permission narrower than "read cookies"

A new permission — name TBD, `session_capture` used below as a placeholder —
with a correspondingly new structural requirement, following the same
pattern `permissions.md` already documents for `webview`/`webview` and
`authentication`/`external_auth`: `session_capture` requires `webview`, and
requires `external_auth` (it writes straight into the credential store; the
plugin never receives raw values — see below).

What it grants is deliberately narrower than "read this web view's cookies":

- **Only fires once, immediately after a `presentForResult`-style flow's own
  completion predicate matches.** Not a standing capability, not a live
  cookie-jar API, not observable per navigation.
- **The plugin never sees the captured values.** It declares, in the
  manifest, a small allowlist of what to capture and which credential-store
  key each one lands in — e.g. "the `cookie` header value → `session_cookie`",
  "the `x-goog-pageid` response header, if present → `page_id`". The host
  extracts exactly those named items and writes them straight to
  `SwayveCredentialStore` under the declared keys. Plugin code calls
  `readSecret` afterward exactly as it does today for a manually pasted
  cookie — the capture path and the manual-paste path converge on the same
  storage, so a plugin's provider code needs **no changes** to consume
  either.
- **Scoped to the same host(s) the sign-in flow itself navigated to** — not
  "any cookie on the device," not "any header from any response."

This keeps the plugin's actual code surface identical to today: `youtube_music`
would still just call `credentials.readSecret(kSessionCookieSettingId)` and
`credentials.readSecret(kPageIdSettingId)`. What changes is *how those keys
get populated* — a captured value instead of a pasted one — which is exactly
why this is additive to the beta's shipped fix rather than a replacement
for it. Manual paste stays as the fallback path for platforms Phase 2
doesn't reach yet (see below) and for anyone who'd rather not use the
web view flow at all.

### Sketch of the new SDK surface (not `presentForResult`)

```dart
// New method, new controller capability — presentForResult is untouched.
abstract interface class SwayveSessionCaptureController {
  /// Presents [start] like presentForResult; on the same completion match,
  /// extracts exactly the artifacts named in the manifest's
  /// `session_capture` block and writes them to the credential store under
  /// their declared keys. Returns success/failure and the completion URL —
  /// never the captured values themselves.
  Future<SwayveSessionCaptureResult> presentForSessionCapture(
    Uri start, {
    required bool Function(Uri url) isComplete,
    Duration? timeout,
  });
}
```

### Sketch of the manifest declaration

```json
"permissions": ["webview", "external_auth", "session_capture"],
"session_capture": {
  "hosts": ["music.youtube.com"],
  "capture": [
    { "from": "cookie_header", "as_secret": "session_cookie" },
    { "from": "page_script:youtube_page_id", "as_secret": "page_id" }
  ]
}
```

**Why `page_script:youtube_page_id` and not `response_header:x-goog-pageid`,**
as an earlier sketch of this proposal had it: `webview_flutter` has no API for
reading response headers off in-webview network traffic, so
`response_header:*` was never implementable on the platform this feature
actually targets. The mechanism that shipped instead runs a fixed,
host-owned JavaScript snippet through `runJavaScriptReturningResult` —
ported from the existing desktop bookmarklet's `window.ytcfg.data_` parsing
logic (`plugins_settings_screen.dart`'s `_pageIdBookmarklet` in the host
app). Same technique — read the page id out of `ytcfg` state the page
already has — different trigger: a bookmarklet the user runs by hand on
desktop becomes a snippet the host runs automatically on completion. The
vocabulary stays closed and host-owned either way: a plugin still names only
*what* to capture, never *how*.

Both sketches were illustrative rather than final when this proposal was
written, and the point being validated here still holds now that one of
them shipped: the *shape* of the restriction (declared, host-scoped, named
artifacts only, no raw plugin access) is enough to implement automatic
capture without widening any existing permission.

## Threat model notes

- The host enforces the allowlist, not the plugin — a plugin cannot ask for
  "everything," only for named cookie/header values the validator checks
  against a closed vocabulary (mirroring how `network.hosts` is validated
  today).
- Because captured values never reach plugin code, a plugin that never
  declares `session_capture` is unaffected regardless of what a sign-in page
  it opens via ordinary `presentForResult` might set.
- This is materially more sensitive than a manually pasted cookie the user
  chose to copy themselves, so it likely needs its own consent copy at
  install/grant time distinct from `external_auth`'s existing text — "this
  plugin will automatically detect your sign-in session after you sign in"
  — rather than folding silently into `external_auth`'s current wording.

## Why mobile-first

iOS (`WKWebView`) and Android (`WebView`) both have mature Flutter bindings
(`webview_flutter`) with navigation delegates and reasonably clean access to
response headers and cookies through supported, first-party plugin APIs.
Desktop is a materially bigger lift: Flutter has no official desktop
`webview_flutter` backend, and the unofficial options (`webview_windows`,
WebKitGTK bindings for Linux) are less mature and would need their own
integration and security review — work this proposal explicitly does not
scope.

**Phase 2, when built, targets iOS and Android only.** Windows and Linux
keep the manual-paste flow shipped in the beta (`youtube_music`'s
`session_cookie` / `page_id` settings) until desktop web view embedding is
scoped as its own piece of work. This also means the app's current desktop
`presentForResult` stub (`_UnsupportedWebViewController` in
`personalmusicsync/lib/core/plugins/plugin_host_context.dart`) is
intentionally left alone — no desktop web view work starts as part of this
phase.

## Explicit non-goals for this phase

- No changes to `presentForResult` or `SwayveWebViewController`.
- No Windows or Linux web view embedding.
- No implementation — this is the design to react to before any of the
  above is scoped as real work.
