# Permissions

A permission answers *what may this plugin touch?* — as distinct from a
capability, which answers *what can this plugin answer?* The two vocabularies
are separate and both closed. See
[architecture.md](architecture.md#capabilities-and-permissions-are-different-questions)
for why.

> Examples below reference `plugins/example` and `plugins/youtube_music` as
> worked cases. Both now live in
> [`Daza-Swayve-plugins`](https://github.com/dazacode/Daza-Swayve-plugins),
> not in this repository — the reasoning still applies, only the path changed.

Permissions are declared in the manifest:

```json
"permissions": ["network", "webview"]
```

They are enforced by the host, not by convention. Reaching for a facility you
did not declare throws `SwayvePermissionDeniedException` **synchronously**, at
the point of access — not later, not as a failed future:

```dart
// Manifest declares ["network"] only.
final storage = context.storage;   // throws SwayvePermissionDeniedException
                                   //   (permission: SwayvePermission.localPluginStorage)
```

The SDK ships one reference mixin, `SwayvePermissionEnforcement`, which the host
mixes into its real context and the harness mixes into
`FakeSwayvePluginContext`. A test that passes against the fake will not fail
differently on device. It exposes `hasPermission`, `requirePermission`,
`guard` and `guardAll` (for a facility gated on more than one permission, such
as `sessionCapture`'s `webview` + `external_auth`), and requires implementers
to return the **effective** set — the intersection of declared and granted,
not merely what the manifest asked for. See [testing.md](testing.md).

---

## The five permissions

### `network`

**Grants** outbound HTTP(S) through `SwayveHttpClient`, restricted to the
hostnames listed in the manifest's `network.hosts`.

```dart
abstract interface class SwayveHttpClient {
  Future<SwayveHttpResponse> get(Uri url, {Map<String, String>? headers,
      Duration? timeout, SwayveCancellationToken? cancel});
  Future<SwayveHttpResponse> post(Uri url, {Map<String, String>? headers,
      Object? body, Duration? timeout, SwayveCancellationToken? cancel});
  Future<SwayveHttpResponse> postMultipart(Uri url, {Map<String, String>? headers,
      required Map<String, String> fields, required SwayveMultipartFile file,
      Duration? timeout, SwayveCancellationToken? cancel});
}
```

**Does not grant** raw sockets, WebSockets, listening on a port, `dart:io`
(which the SDK forbids outright), requests to hosts outside `network.hosts`, or
any request the host chooses to refuse. `GET`, `POST` and a single-file
`postMultipart` are the whole surface — the last of which exists only to feed
the `personal_library_push` capability's `SwayveLibraryPushProvider.uploadTrack`
its bytes; it is buffered, not streamed, and takes exactly one file, the same
"not a general primitive" stance every method here takes.

Hosts are matched against the declared list, with `*.host.tld` matching one or
more leading labels. A request to an undeclared host is refused by the client
before it leaves the device.

### `webview`

**Grants** the host permission to render a plugin-requested web view, driven
through a single narrow method:

```dart
abstract interface class SwayveWebViewController {
  Future<Uri?> presentForResult(Uri start,
      {required bool Function(Uri) isComplete, Duration? timeout});
}
```

The plugin supplies a start URL and a predicate that recognises the completion
URL; the host presents the view, watches navigation, dismisses it, and returns
the matching `Uri` — or `null` if the user cancelled or the timeout elapsed.

**Does not grant** injecting JavaScript into the host's own UI, reading cookies
or storage belonging to Swayve, arbitrary DOM access, keeping a web view alive
in the background, or presenting a view that the user cannot dismiss. The web
view is a modal the user is always able to walk away from.

This is also the permission behind `SwayvePlayableKind.webEmbed`: a plugin whose
playback requires an embedded surface declares `webview` and returns a
`SwayveWebEmbed` describing what the host should render and which controls it
may drive.

### `external_auth`

**Grants** a host-mediated authentication flow and access to the plugin's own
credential slot:

```dart
abstract interface class SwayveCredentialStore {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  Future<void> deleteSecret(String key);
}
```

It is also what makes a `type: "secret"` setting legal — declaring one without
`external_auth` is a manifest error.

**Does not grant** access to the user's Swayve account credentials, to another
plugin's credential slot, to the device keychain generally, or the ability to
initiate an auth flow the user did not start. Signing in is a user action.

### `local_plugin_storage`

**Grants** read/write access to a small key/value namespace belonging to this
plugin:

```dart
abstract interface class SwayvePluginStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
}
```

Keys match `^[A-Za-z0-9_.-]{1,128}$`. Values are strings — serialise structured
data yourself.

**Does not grant** filesystem access, paths, directories, file handles, another
plugin's namespace, or a place to keep secrets. `clear()` clears *this* plugin's
namespace and nothing else.

### `clipboard`

**Grants** writing to the system clipboard.

**Does not grant** *reading* the clipboard. Ever. There is no read method, in
this version or any planned one — a clipboard read is an exfiltration primitive
with no legitimate plugin use case, and the asymmetry is the point.

---

## Capabilities and permissions: two different checks

Declaring a capability says something about the permissions you should hold —
but how strongly depends on the capability, and the validator makes the
distinction explicit with two separate rules.

### Structural: capability requires permission — ERROR

Exactly three capabilities are unusable without a permission, because the
capability and the permission(s) describe *the same act*:

| Capability | Requires | Why it is structural |
|---|---|---|
| `webview` | `webview` | The capability is "this plugin needs the host to render a web view". The permission is what grants that. |
| `authentication` | `external_auth` | The capability is a host-mediated auth flow. The permission is what grants it, plus the credential slot the flow writes to. |
| `session_capture` | `webview` **and** `external_auth` | The capability is a web view presentation (`webview`) that ends by writing straight into the credential store (`external_auth`) — both halves of `webview` + `authentication` at once, in a single flow. |

Declaring a capability without every permission it requires describes a
plugin that cannot do the thing it says it does, so each missing one is an
**error** (`capability_requires_permission`) — `session_capture` with neither
permission granted produces two diagnostics, one per missing permission.

### Structural: capability requires capability — ERROR

One capability is unusable without *another declared capability*, rather than
a permission:

| Capability | Requires | Why it is structural |
|---|---|---|
| `personal_library` | `authentication` | The capability is the signed-in user's own liked tracks. There is no "own" without a session, and `authentication` is what a plugin declares to say it can obtain one. |
| `personal_library_push` | `personal_library` | The capability is *writing* to that same signed-in user's library. There is no "push to my library" without first declaring the capability that reads one — so it requires `personal_library` itself, not `authentication` reached past it. |

```
  ERROR   capabilities: 'personal_library' requires capability 'authentication'
```

Code: `capability_requires_capability`. This is deliberately a separate rule
from the one above, not another row in that table: holding `external_auth`
says a plugin *may* touch the credential store, but says nothing about whether
it runs a sign-in flow at all. A manifest could hold `external_auth` through a
`type: "secret"` setting alone (see [below](#credentials)) and still have no
`authentication` capability to put a session behind `personal_library`. See
[plugin-manifest.md](plugin-manifest.md#1c-capability-requires-capability--error)
for the validator rule.

### Advisory: capability expects network — INFO

The other eleven capabilities — `search`, `catalog`, `streaming`, `metadata`,
`lyrics`, `scrobbling`, `artwork`, `playlist_read`, `artist_activity`,
`personal_library`, `personal_library_push` — *usually* reach an external
service. Declaring one without `network` produces an **info note**
(`capability_expects_network`), never a warning and never an error, and
`--strict` does not promote it.

That choice is deliberate, and the reasoning is the interesting part:

**Whether a plugin actually opens a connection is not statically decidable from
a manifest.** A `search` provider can perfectly well serve a catalogue that ships
inside the plugin. A `catalog` provider can index files the host already holds.
Making the implication an error would force an honest offline plugin to declare
a permission it never uses — which is precisely the over-permissioning this
model exists to make visible.

`plugins/example` is the worked case. It declares `search` and `catalog`, serves
a hand-written fixture catalogue compiled into itself, and declares
**`"permissions": []`**. It touches no host, no disk and no socket. Under an
error-level implication it could not exist without lying; as things stand it
emits two info notes and passes `--strict` clean.

The severity choice follows directly from that: `--strict` promotes warnings to
errors, so a warning here would fail CI for a plugin whose only fault is
honesty. INFO is the only severity that says "look at this" without saying
"this is wrong".

### Under-declaration is caught at runtime

Nothing is lost by declining to guess in the validator, because the real
enforcement is exact and happens where the answer is actually knowable:

```dart
// Manifest declares no permissions.
final response = await context.http.get(url);
//                       ^^^^ throws SwayvePermissionDeniedException
//                            synchronously, before any request is composed
```

`context.http` throws unless `network` is declared, and
`FakeSwayvePluginContext` reproduces that through the same
`SwayvePermissionEnforcement` mixin the host uses. A plugin that really does need
the network therefore fails **its own test suite**, on the line that over-reached,
long before a user sees it. See [testing.md](testing.md).

### Over-declaration stays a warning

Over-declaration is the direction that costs a user trust, so it is a warning
that `--strict` does promote:

```
  WARNING permissions: 'network' is declared but no declared capability needs it; drop it or add the capability that does
```

Code: `permission_not_implied`. A permission counts as justified when any
declared capability implies it, structurally or advisorily. Two exemptions:

- **`local_plugin_storage` and `clipboard` are self-justifying.** They are host
  facilities rather than provider interfaces, so no capability could ever imply
  them. Declaring either is never over-permissioning and never warns.
- **`external_auth` is also justified by a `type: "secret"` setting**, since a
  pasted API key is a credential even without an auth flow.

---

## An allow-list is a claim about what you do

`network.hosts` is not paperwork. It is the list a user can read to know where a
plugin's traffic goes, so what you leave out matters as much as what you put in.

The reference plugin makes this concrete. `plugins/youtube_music` declares:

```json
"network": { "hosts": ["music.youtube.com", "www.youtube.com", "i.ytimg.com"] }
```

Two decisions are visible in that line:

- **`*.googlevideo.com` is deliberately absent.** It is the media-CDN host
  reached only by *stream extraction* — reproducing the signature logic of a
  player the service controls. That plugin refuses to do it, resolving playback
  to the official embedded player instead. Declaring the CDN would advertise
  exactly the capability it does not have, and least privilege means not asking
  for reach you will not use.
- **`www.youtube.com` is present** because that is where the embedded player
  lives, and the plugin hands its URL to the host.

The consequence is a real, visible functional gap, and it was left open rather
than closed by widening the list: YouTube Music serves album and artist artwork
from `lh3.googleusercontent.com`, which is not declared, so those references are
**dropped and reported as `null`**. Closing that would be a one-line manifest
change — and it is not made, because widening the hosts a plugin may reach is a
change a user should see and approve, not something an author slips in to make a
grid look nicer.

That plugin also filters outbound URLs against its own copy of the list before
the host is ever asked, and its test suite checks every request against
`plugin.json` itself rather than against the constant in the code. Belt and
braces: manifest/code drift becomes a loud failure instead of a silent one.

---

## Explicitly not grantable in v1

There is no permission string for any of the following, and none is planned as
a plugin-facing grant:

| Not grantable | Why |
|---|---|
| The user's music files | A plugin adds sources; it does not read the library. There is no path, handle or query that reaches local media. |
| Swayve account credentials | A plugin authenticates to *its own* service. Swayve's identity is never delegated. |
| Another plugin's storage | See [isolation](#storage-isolation) below. |
| Arbitrary filesystem paths | The SDK has no `dart:io`. There is no file API of any kind on the plugin surface. |
| Device secrets | No keychain enumeration, no device identifiers, no advertising ids, no contacts, no location. |
| Background execution | Plugins run when the host calls them. There is no scheduler, no wake-up, no periodic task. |

If a plugin's design requires one of these, the answer is not a new permission —
it is a different design, or a host feature that every plugin can use.

---

## Storage isolation

Each plugin gets its own storage namespace, keyed by its manifest `id`. The
namespace is created by the host at `resolvePermissions`, and the plugin never
sees the key that identifies it.

```
host storage
├── app.swayve.plugins.youtube_music/
│     region_cache      = "US"
│     last_cursor       = "CAAQAA"
├── app.swayve.plugins.example/
│     seen_intro        = "true"
└── dev.alice.swayve.demo/
      …
```

Properties the host must uphold:

- **No cross-plugin reads.** There is no API taking a plugin id, so plugin A
  cannot name plugin B's namespace. Isolation is by absence of a parameter, not
  by an access check that could be forgotten.
- **No key enumeration.** `SwayvePluginStorage` has no `keys()` or `list()`.
  A plugin can read what it knows the name of and nothing else. This keeps a
  future shared-namespace mistake from becoming a browsable directory.
- **Uninstall clears.** Removing a plugin removes its namespace.
- **Not a secret store.** Plugin storage is for cursors, cached ids, small
  preferences. Tokens go to the credential store. A plugin that writes a bearer
  token into `SwayvePluginStorage` is doing something wrong even though nothing
  will stop it.
- **Not durable across devices.** Nothing here syncs. Treat every value as
  disposable cache; if losing it breaks the plugin, it was the wrong place.

---

## Credentials

The credential story is deliberately narrow, and parts of it are **v1-partial**.
What follows separates what is specified from what is built.

### Host-mediated by construction

A plugin never performs its own token exchange in a context the host cannot see.
The flow is:

1. The plugin declares `authentication` (⇒ `external_auth`) and, if it needs a
   web step, `webview`.
2. The user starts sign-in from the host's UI. The host calls
   `SwayveAuthProvider.authenticate()`.
3. The plugin asks the host to present the provider's authorization URL via
   `SwayveWebViewController.presentForResult`, with a predicate that recognises
   the redirect.
4. The host returns the redirect `Uri`. The plugin exchanges it for a token
   using `SwayveHttpClient`, against a host it declared in `network.hosts`.
5. The plugin stores the result with `SwayveCredentialStore.writeSecret` and
   emits a new `SwayveAuthState` on `authStateChanges`.

Every step the plugin takes runs through a host facility that is permission-
gated, host-timed and host-loggable. There is no step where the plugin holds a
capability the host did not hand it.

A plugin whose sign-in has no redirect URL to hand back — only page state, a
cookie, a value sitting in the page's own script context — declares
`session_capture` instead of driving steps 3-5 itself. The host still presents
the web view and watches for the same kind of completion match, but on match
it extracts exactly the artifacts the manifest's `session_capture.capture`
list names and writes them straight into `SwayveCredentialStore` — the plugin
never sees step 4's redirect equivalent at all. See
[capabilities.md](capabilities.md#session_capture) for the full shape.

### `type: "secret"` settings

A `secret` setting is a credential entered by hand rather than obtained through
a flow — an API key, a self-hosted server token. Its value goes to the
credential store, **never** to plugin storage, and is read back with
`readSecret`, not `SwayveSettingsView.value`. Declaring one without
`external_auth` is a manifest error.

### Tokens and logs

`SwayvePluginLogger` is host-implemented, and the host redacts secrets it
recognises. That is a safety net, not a contract: **plugins must not log tokens,
authorization headers, cookies or redirect URLs containing a code.** Assume
every log line may be read by a support engineer, and write accordingly.

```dart
// Wrong — the redirect carries the authorization code.
context.log.debug('auth redirect: $uri');

// Right.
context.log.debug('auth redirect received (${uri.host})');
```

### What is not built yet

Honest boundaries, so nobody plans against a promise:

| Piece | Status |
|---|---|
| `SwayveCredentialStore` interface + in-memory fake | **Specified and available in the SDK.** Tests can exercise the full flow. |
| Host-side secure backing (OS keychain / keystore) | **Not implemented in v1** — the client has no plugin system at all yet, so there is no host implementation to point at. See [host-integration.md](host-integration.md). |
| Token refresh scheduling | **Not implemented in v1.** A plugin refreshes lazily, on the next call that needs a valid token. There is no background refresh, because there is no background execution. |
| Per-plugin credential encryption at rest | **Planned.** The current specification says only *where* a secret goes, not how it is protected on disk; that is a host obligation to be specified alongside the loader. |
| Credential revocation on plugin removal | **Specified as a host obligation**, not yet implemented: removing a plugin must delete its credential slot as well as its storage namespace. |

Until the host side exists, treat the credential API as the shape you should
write against, and assume nothing about durability or at-rest protection.

---

## See also

- [capabilities.md](capabilities.md) — the other half of the declaration
- [plugin-manifest.md](plugin-manifest.md#cross-field-validation-rules) — the validator rules that enforce these implications
- [SECURITY.md](../SECURITY.md) — the threat model these permissions exist to shape
