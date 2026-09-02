# The plugin manifest (`plugin.json`)

Every plugin has exactly one `plugin.json` at the root of its directory. It is
the only file the host reads before deciding whether to load anything, so it has
to be complete, honest and machine-checkable on its own.

- Schema `$id`: `https://swayve.app/schema/swayve-plugin.schema.json`
- JSON Schema draft: `https://json-schema.org/draft/2020-12/schema`
- Local copy: [`schema/swayve-plugin.schema.json`](../schema/swayve-plugin.schema.json),
  with a companion [`schema/README.md`](../schema/README.md)

> Examples below name plugin directories as worked cases. No plugin lives in
> this repository — see [`swayve-plugin-example`](https://github.com/dazacode/swayve-plugin-example)
> for one you can read and run. The reasoning applies whatever the path is.

`additionalProperties: false` applies at the top level **and inside every nested
object**. An unrecognised key is an error, not a comment. This is deliberate: a
typo like `"permisions"` must fail loudly rather than silently granting nothing.

The manifest does **not** carry a `$schema` key — the property set is closed, so
point your editor at the schema file instead of having the file declare itself.

Validate with:

```bash
dart run tools/validate_plugin.dart ../my_plugin
```

---

## Required fields

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | integer | `5` as of the `personal_library_push` capability (`4` as of `session_capture`, `3` as of `personal_library`); `1` through `4` still validate. Rejected only if newer than the build understands. Not the plugin's version — see [versioning.md](versioning.md). |
| `id` | string | Reverse-DNS. Regex `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$` — at least three segments, lowercase, digits and `_` allowed but not as the first character of a segment. Max 128 characters. |
| `name` | string | 1–64 characters, human readable, no emoji. This is what the user sees in Explore and in settings. |
| `description` | string | 1–280 characters. One sentence describing what the plugin adds, not who wrote it. |
| `version` | string | Strict SemVer 2.0.0. `1.0`, `v1.0.0` and `1.0.0.1` are all rejected. |
| `author` | object | `{ "name": string (required, 1–64), "url": uri?, "email": email? }` |
| `license` | string | SPDX identifier, e.g. `Apache-2.0`, `MIT`. Must match the plugin's `licenses/` directory. |
| `swayvePluginApi` | integer | The SDK major API level the plugin targets. `1` in v1. |
| `minimumSwayveVersion` | string | SemVer of the oldest Swayve client this plugin works against. |
| `runtime` | enum | `compiled` \| `bundled`. See [platforms.md](platforms.md). |
| `platforms` | array&lt;enum&gt; | Non-empty, unique. Any of `android`, `ios`, `windows`, `macos`, `linux`. |
| `capabilities` | array&lt;enum&gt; | Non-empty, unique. Closed vocabulary — see [capabilities.md](capabilities.md). |
| `permissions` | array&lt;enum&gt; | Unique. **May be empty.** Closed vocabulary — see [permissions.md](permissions.md). |
| `entrypoint` | string | Regex `^[a-z][a-z0-9_]*$`. Names the plugin's **directory and Dart library** — see below. |

`permissions` being allowed to be empty while `capabilities` must be non-empty is
not an oversight. A plugin that answers no questions is not a plugin; a plugin
that needs no host facilities is entirely reasonable. `plugins/example` is
exactly that: `"permissions": []`, and it passes `--strict` clean.

### What `entrypoint` actually names

`entrypoint` names two things, and **not** a Dart function:

1. the plugin's **directory** under `plugins/` — enforced as an error by the
   validator (`directory_name_mismatch`);
2. the plugin's **Dart library**, e.g. `"nebula_music"` ⇒
   `package:nebula_music/nebula_music.dart`.

The registration symbol — the `SwayvePluginFactory` the host calls — is a
separate, ordinary Dart identifier. `plugins/example` happens to name its
factory `example()`, matching the entrypoint, because that is a legal
lowerCamelCase identifier. `plugins/nebula_music` cannot: `nebula_music()`
would violate `non_constant_identifier_names` and fail this repository's
analysis baseline, so its factory is **`createNebulaMusicPlugin()`**.

Do not assume the factory name from the manifest. The manifest names the library;
the library exports whatever it exports.

## Optional fields

| Field | Type | Notes |
|---|---|---|
| `homepage` | uri | `http`/`https`. Where a user should go to learn about the plugin. |
| `repository` | uri | `http`/`https`. Where its source lives. |
| `icon` | string | Relative path under `assets/`, ending `.png` or `.svg`. Subject to rule 10, and the file must exist at packaging time (`icon_file_missing`). |
| `source` | object | How the plugin presents itself as a place a query can be sent. See [below](#source). |
| `media` | object | `{ "streamable": bool, "downloadable": bool, "offlineCache": bool }` — all default `false`. |
| `settings` | array&lt;SettingDescriptor&gt; | Max 32 entries. See [below](#settings). |
| `network` | object | `{ "hosts": [string] }` — the outbound hostnames the plugin will contact. Wildcards of the form `*.host.tld` are allowed. |
| `session_capture` | object | `{ "hosts": [string], "capture": [SessionCaptureEntry] }` — required when the `session_capture` capability is declared. See [below](#session_capture). |
| `timeouts` | object | `{ "requestMs": int 1000–30000, "operationMs": int 1000–60000 }`. Bounds, not guarantees — the host applies its own hard limits regardless. |
| `keywords` | array&lt;string&gt; | Max 10 entries, lowercase. |

### `source`

```jsonc
"source": {
  "sourceId": "wavecast",          // required; ^[a-z][a-z0-9_]*$, max 64
  "displayName": "Wavecast",       // optional; falls back to sourceId
  "iconName": "wavecast",          // optional; a glyph name, NOT a path
  "contentTypes": ["songs", "artists"],   // optional; songs|albums|artists|videos
  "availability": "ready"            // optional; a declared default, see below
}
```

The whole object is optional, and a plugin that is not a source should leave it
out: a metadata or lyrics plugin enriches what the host already has and is never
somewhere a query is sent.

**`contentTypes` is declared, never derived.** The obvious alternative is for the
host to read it off the capability list — `catalog` means it has albums, and so
on — and that is wrong in both directions. A catalogue provider for a service
built on user uploads has no albums to offer however firmly it declares
`catalog`; a service with a video half and a music half declares one `search`
capability for two very different things. Deriving would have the host inventing
claims on a plugin's behalf and then rendering them as though the plugin had made
them.

**`iconName` is a glyph name, not `icon`.** `icon` is the plugin's own artwork,
shipped in the bundle and rendered at whatever size the settings screen wants.
`iconName` is a mark small enough for a source chip, drawn by the host from its
own icon set so that every source in a filter row is in one visual language. A
name the host has never heard of falls back to a generic source mark, so an
unfamiliar one is not an error — and a plugin shipping neither still appears
everywhere it should.

**There is no `canSearch`.** Whether a text query means anything to a source is
already answered by the `search` capability, and a second place to say it is a
second place for it to be wrong. `source` deliberately does not repeat the
capability list.

**`availability` is a declared default, not an observation.** Whether a service
can answer *right now* is knowable only to a running plugin, so in practice a
manifest either omits this or says `ready`; it is in the vocabulary for the
plugin that ships switched off until somebody signs in. The live value is
republished by the running plugin through `SwayveSourceDescriptor`.

### `media` is three independent facts

`streamable`, `downloadable` and `offlineCache` are separate booleans because
they are separate truths. A track can be streamable and not downloadable
(licensing). It can be downloadable and not currently on-device (you have not
downloaded it). It can be on-device and no longer streamable (the source
removed it). Never derive one from another, in the manifest or at runtime —
`SwayveAvailability` carries the same three-way split for exactly this reason.

`media` describes the plugin's *ceiling*. A `SwayvePlayableSource` returned at
runtime must agree with it: a plugin declaring `"streamable": false` cannot
return a streamable source. `plugins/example` sets all three to `false` and
registers no `SwayveStreamProvider` at all — a plugin may contribute catalogue
data while claiming no playback rights whatsoever.

### `network.hosts` is an allow-list, not documentation

The host restricts `SwayveHttpClient` to the declared hosts. A request to an
undeclared host fails at the client, not at the network. Listing hosts you do
not use is noise; omitting hosts you do use is a bug that will surface as a
runtime failure in the field rather than at review time.

The reference plugin takes this seriously in both directions — see
[permissions.md](permissions.md#an-allow-list-is-a-claim-about-what-you-do).

### `session_capture`

```jsonc
"session_capture": {
  "hosts": ["music.nebula.example"],           // required; scopes the capture flow
  "capture": [
    { "from": "cookie_header", "as_secret": "session_cookie" },
    { "from": "page_script:youtube_page_id", "as_secret": "page_id" }
  ]
}
```

Required — and only meaningful — alongside the `session_capture` capability
(rule 12; see [below](#12-session_capture-is-well-formed)). `hosts` scopes the
flow the same way `network.hosts` scopes outbound requests, and must be
non-empty. Each `capture` entry names one artifact to extract on completion:

- **`from`** is drawn from a closed, host-owned vocabulary — currently
  `cookie_header` (the session cookie the platform's native cookie manager
  holds for `hosts`) and `page_script:youtube_page_id` (a fixed JavaScript
  snippet the host runs via `runJavaScriptReturningResult`; **never** a
  plugin-supplied script). A plugin names *what* to capture, never *how* — the
  extraction mechanism behind each `from` value lives entirely in the host.
- **`as_secret`** is the credential-store key the extracted value is written
  under, and must match the `id` of a `settings` entry with `type: "secret"`
  (rule 12 again). The plugin reads it back with
  `SwayveCredentialStore.readSecret`, exactly as it would for a value the user
  pasted in by hand — the capture path and the manual-paste path converge on
  the same storage.

See [capabilities.md](capabilities.md#session_capture) for the SDK surface
this block drives, and [permissions.md](permissions.md#structural-capability-requires-permission--error)
for why `session_capture` requires both `webview` and `external_auth`.

### `personal_library_push` adds no manifest block

Unlike `session_capture`, declaring the `personal_library_push` capability
does not introduce any new top-level manifest key. There is nothing the host
needs to know about the shape of a push ahead of time — no hosts to scope, no
artifacts to name — because the only host-owned mechanism it depends on is
already covered by `network.hosts`. Whatever a plugin wants to tag or
organise a pushed track with (a fixed label, for instance) is entirely the
plugin's own business, expressed however it likes on its own side of
`uploadTrack` — not something the manifest, or the host, needs to model. See
[capabilities.md](capabilities.md#personal_library_push) for the provider
interface this capability drives.

---

## Complete annotated example

This is `plugins/nebula_music/plugin.json`, with comments added. JSON does not
support comments — the real file has none.

```jsonc
{
  // Manifest format version. Bumped only when the schema itself changes.
  "schemaVersion": 1,

  // Reverse-DNS id. `app.swayve.plugins.*` is reserved for first-party plugins;
  // community plugins use `dev.<username>.swayve.*`. The last segment matches
  // `entrypoint` by convention (rule 6).
  "id": "app.swayve.plugins.nebula_music",

  "name": "Nebula Music",
  "description": "Adds Nebula Music search, browsing and playback to Swayve.",

  // The plugin's own version. Independent of every other version in this file.
  "version": "0.1.0",

  // `name` is required; `url` and `email` are optional. First-party plugins
  // must use exactly "Swayve" here (rule 8).
  "author": {
    "name": "Swayve",
    "url": "https://github.com/dazacode/swayve-plugins"
  },

  "license": "Apache-2.0",
  "homepage": "https://github.com/dazacode/swayve-plugins/tree/main/plugins/nebula_music",
  "repository": "https://github.com/dazacode/swayve-plugins",

  // SDK major API level this plugin was written against.
  "swayvePluginApi": 1,

  // The oldest Swayve client that can load it. Raising this is a compatibility
  // decision, not a formality — see versioning.md.
  "minimumSwayveVersion": "0.1.0",

  // Source lives in this repo and is compiled into Swayve builds. Not
  // downloaded at runtime. See platforms.md.
  "runtime": "compiled",

  // No `macos` here because this plugin has never been exercised there.
  // `linux` was added later than the rest, and only once this plugin had
  // actually run against a Linux Swayve build — not the day the code first
  // compiled for it. That caution found a real bug rather than a
  // hypothetical one: see platforms.md's platform-matrix section.
  // Claim only what you have run.
  "platforms": ["android", "ios", "windows", "linux"],

  // Five capabilities. Four map to provider interfaces; `webview` does not —
  // it declares that this plugin's playback needs a host-rendered web surface.
  // Omitting it would leave the `webview` permission unjustified, and the
  // validator would report the plugin as over-permissioned.
  "capabilities": ["search", "catalog", "streaming", "webview", "artwork"],

  // `network` for the API calls, `webview` for the embedded player.
  "permissions": ["network", "webview"],

  // Names the directory (plugins/nebula_music/, rule 7) and the Dart library.
  // NOT the factory function, which is createNebulaMusicPlugin().
  "entrypoint": "nebula_music",

  // Ceiling for what this plugin can offer. Downloads are off: playback is a
  // web embed, which is a page to render, not bytes to keep.
  "media": { "streamable": true, "downloadable": false, "offlineCache": false },

  // The complete outbound allow-list. `*.googlevideo.com` is deliberately
  // absent — it is the media CDN reached only by stream extraction, which this
  // plugin refuses to do. `www.nebula.example` is present because that is where
  // the official embedded player lives.
  "network": {
    "hosts": ["music.nebula.example", "www.nebula.example", "i.ytimg.com"]
  },

  // Advisory bounds for a single request and a whole operation.
  "timeouts": { "requestMs": 10000, "operationMs": 20000 },

  // Rendered by the host on the plugin's settings page. The plugin never draws
  // this UI itself.
  "settings": [
    {
      "id": "region",
      "type": "select",
      "label": "Region",
      "description": "Catalogue region sent to Nebula Music. Availability is regional.",
      "default": "US",
      "options": [
        { "value": "US", "label": "United States" },
        { "value": "GB", "label": "United Kingdom" },
        { "value": "IN", "label": "India" }
      ]
    }
  ],

  "keywords": ["nebula", "music", "streaming", "search", "catalog"],

  // Relative, under assets/, .png or .svg. Rule 10 rejects anything else.
  "icon": "assets/icon.svg"
}
```

---

## Diagnostics

Every diagnostic carries a **stable machine code**. Codes are public API: CI
jobs, dashboards and the host may match on them, so a code is never renamed or
reused for a different meaning. New checks get new codes. `--json` emits the
code, severity, message, an RFC 6901 JSON pointer to the offending value, and —
where it is known — the source file and line.

Severity: **ERROR** blocks packaging and loading · **WARNING** is reported and
becomes an error under `--strict` (which is what CI runs) · **INFO** is advisory
and is never promoted by `--strict`.

The validator emits several families of code. The cross-field rules below are
the ones you will meet most, but they are not the whole list; the structural,
compatibility and settings families are just as real.

### Structural codes (the schema's own checks)

| Code | Meaning |
|---|---|
| `manifest_not_found` | No `plugin.json` in the directory |
| `manifest_unreadable` | It exists but could not be read |
| `manifest_malformed_json` | Not well-formed JSON |
| `manifest_not_object` | The top level is not a JSON object |
| `field_required` | A required property is absent |
| `field_unknown` | A property `additionalProperties: false` forbids |
| `field_type` | Wrong JSON type |
| `field_pattern` | A string violated its `pattern` |
| `field_enum` | A value outside a closed vocabulary |
| `field_length` | A string or array too short or too long |
| `field_range` | A number outside `minimum`/`maximum` |
| `field_duplicate` | A repeat in an array declared `uniqueItems` |
| `field_const` | A `const`-valued field carries something else |
| `field_emoji` | Emoji in a field that forbids them (`name`) |

`field_emoji` is enforced in the validator rather than as a schema `pattern`,
because a regex over the emoji planes is far harder to read than the rule it
encodes.

### Compatibility codes

| Code | Severity | Meaning |
|---|---|---|
| `unsupported_schema_version` | error | `schemaVersion` is not the one this build implements |
| `unsupported_plugin_api` | error | `swayvePluginApi` is above this build's API level |

Both are phrased the way the host must phrase them to a user: the plugin is
fine, Swayve is behind. See [versioning.md](versioning.md).

---

## Cross-field validation rules

Schema validation catches shape. These rules catch *incoherence* — a manifest
that is well-formed but describes something that cannot work.

### 1a. Capability requires permission — ERROR

Exactly three capabilities are **structurally** unusable without a permission,
because the capability and the permission(s) describe the same act:

| Capability | Requires permission |
|---|---|
| `webview` | `webview` |
| `authentication` | `external_auth` |
| `session_capture` | `webview` **and** `external_auth` |

```
  ERROR   capabilities: 'webview' requires permission 'webview'   (plugin.json:15)
```

Code: `capability_requires_permission`. Declaring a capability without every
permission it requires describes a plugin that cannot do the thing it says it
does — one diagnostic per missing permission, so `session_capture` with
neither `webview` nor `external_auth` declared produces two.

### 1b. Capability expects network — INFO

The other eleven capabilities — `search`, `catalog`, `streaming`, `metadata`,
`lyrics`, `scrobbling`, `artwork`, `playlist_read`, `artist_activity`,
`personal_library`, `personal_library_push` — *usually* reach an external
service. When one is declared without the `network` permission, the
validator says so and moves on:

```
  INFO    capabilities: 'search' usually reaches an external service; declare the 'network' permission unless this plugin serves purely local data
```

Code: `capability_expects_network`. **INFO, never a warning**, and `--strict`
does not promote it.

The reasoning matters, because this is the rule most likely to look like a
missing check: whether a plugin actually opens a connection is **not decidable
from a manifest**. A `search` provider can serve a catalogue that ships inside
the plugin. Making this an error would force an honest offline plugin to declare
a permission it never uses — the exact over-permissioning the model exists to
prevent. Real enforcement lives at runtime and is exact; see
[permissions.md](permissions.md#under-declaration-is-caught-at-runtime).

### 1c. Capability requires capability — ERROR

`personal_library` is structurally unusable without `authentication`, for the
same reason `webview` and `authentication` need their own permissions in 1a:
the capability describes the signed-in user's *own* liked tracks, and there is
no "own" without a session. `personal_library_push` follows the identical
shape one level further: it describes *writing* to that same library, so it
requires `personal_library` itself rather than reaching past it straight to
`authentication`.

| Capability | Requires capability |
|---|---|
| `personal_library` | `authentication` |
| `personal_library_push` | `personal_library` |

```
  ERROR   capabilities: 'personal_library' requires capability 'authentication'   (plugin.json:15)
  ERROR   capabilities: 'personal_library_push' requires capability 'personal_library'   (plugin.json:16)
```

Code: `capability_requires_capability`. This is a distinct rule from 1a because
what is missing is another declared capability, not a permission — a manifest
holding `external_auth` without also declaring `authentication` is still an
error here, because the permission grants the credential slot but says nothing
about whether the plugin runs a sign-in flow at all. The same logic applies one
level up: a manifest holding `authentication` (and `personal_library`'s own
requirement is satisfied) still needs `personal_library` declared *explicitly*
before `personal_library_push` is legal — holding the capability underneath a
capability is not the same as declaring the capability itself.

### 2. Unimplied permission — WARNING

A permission that nothing justifies is over-permissioning.

```
  WARNING permissions: 'network' is declared but no declared capability needs it; drop it or add the capability that does
```

Code: `permission_not_implied`. A permission counts as justified when any
declared capability implies it — either structurally (rule 1a) or because it is
one of the eleven network-expecting capabilities. Two further exemptions:

- `local_plugin_storage` and `clipboard` are **self-justifying**. They are host
  facilities rather than provider interfaces, so no capability could ever imply
  them and declaring one is never over-permissioning.
- `external_auth` is also justified by declaring a `type: "secret"` setting.

This is the direction that costs a user trust, which is why it is a warning that
`--strict` promotes, while under-declaration (1b) is only a note.

### 3. `media.downloadable` requires `streaming` — ERROR

```
  ERROR   media: 'downloadable' is true but the plugin does not declare the 'streaming' capability   (plugin.json:22)
```

Code: `downloadable_requires_streaming`. You cannot offer a download of
something you have no way to resolve to bytes.

### 4. `bundled` + `ios` — ERROR

```
  ERROR   platforms: runtime 'bundled' cannot be listed for 'ios'; a runtime-loaded bundle is not permitted on that platform, so the plugin must be 'compiled' or drop 'ios'   (plugin.json:14)
```

Code: `bundled_runtime_not_allowed_on_ios`. A hard stop with no override flag.
Swayve cannot download and execute arbitrary code on iOS. Either set
`runtime: compiled`, or remove `ios` from `platforms`. See
[platforms.md](platforms.md).

### 5. `network` permission with no declared hosts — WARNING

```
  WARNING network: permission declared but no network.hosts listed
```

Code: `network_permission_without_hosts`. An empty allow-list means every
request will be refused at runtime. A warning rather than an error because a
plugin may legitimately be mid-development — but shipping in this state
guarantees a plugin that silently does nothing.

### 6. `entrypoint` should equal the `id`'s last segment — WARNING

```
  WARNING entrypoint: 'ytmusic' does not match the last segment of id ('nebula_music'); they should be the same name
```

Code: `entrypoint_id_mismatch`. Not fatal, because an id is forever and an
entrypoint is a name, but a mismatch makes every log line harder to read.

### 7. Directory name must equal `entrypoint` — ERROR

```
  ERROR   entrypoint: the plugin directory is named 'ytmusic' but entrypoint is 'nebula_music'; they must be identical
```

Code: `directory_name_mismatch`. The most common first failure when copying
`plugins/example` — the directory gets renamed and the manifest does not, or the
reverse. The rule exists because the packager derives the archive name from the
entrypoint, and a mismatch would produce a bundle whose contents do not match
its name. Skipped when the manifest is validated without a directory on disk.

### 8. First-party id requires first-party author — ERROR

Any `id` starting `app.swayve.plugins.` must have `author.name == "Swayve"`.

```
  ERROR   author: id 'app.swayve.plugins.foo' is in the first-party namespace 'app.swayve.plugins.', which requires author.name to be 'Swayve' (found 'Alice')
```

Code: `first_party_author_mismatch`. `app.swayve.plugins.*` is reserved;
community plugins use `dev.<username>.swayve.*`. See
[CONTRIBUTING.md](../CONTRIBUTING.md).

### 9. Pre-1.0 version — INFO

```
  INFO    version 0.1.0 is pre-1.0; the plugin API surface is unstable
```

Code: `prerelease_api_unstable`. Purely advisory. It exists so that a `0.x`
plugin cannot later claim it was never told.

### 10. Path safety — ERROR

Every path-valued field — `icon` today, any future one — must be relative, and
must not start with `/`, contain `..`, contain a drive letter, contain a
backslash, or contain a NUL or other control character.

```
  ERROR   icon: path must be relative to the plugin directory; '../../etc/passwd' escapes the plugin directory
```

Code: `unsafe_relative_path`. The same normalisation rules are enforced again at
extraction time, on the archive's entry names — see
[packaging.md](packaging.md#extraction-safety). Both checks are needed: the
manifest check catches an author's mistake at review time, the extraction check
catches an attacker at load time.

### 11. `source` is reachable — INFO

Both halves are advisory, for the same reason 1b is: what a plugin can
actually be asked for is not decidable from a manifest.

```
  INFO    source: the 'search' capability is declared but source.contentTypes names nothing this source can be asked for, so a host has nothing to offer it under
  INFO    source: declared, but the plugin declares neither 'search' nor 'catalog', so nothing can be asked of it; a plugin that only enriches what the host already has is not a source
```

Codes: `source_declares_no_content_types` (a `search` capability paired with an
empty `source.contentTypes`) and `source_without_reachable_capability` (a
`source` block on a plugin declaring neither `search` nor `catalog`). Neither
promotes under `--strict`.

### 12. `session_capture` is well-formed — ERROR / INFO

Mirrors 11's asymmetric severity, one level over: declaring the capability
with no block to back it up describes a plugin that cannot do the thing it
says it does (**error**), while a block with no capability to run it is dead
configuration nothing will ever execute (**info**). Once a block is present,
its contents are checked regardless of which way that mismatch went.

```
  ERROR   capabilities: 'session_capture' is declared but no session_capture object is present
  INFO    session_capture: declared, but the plugin does not declare the 'session_capture' capability, so this block will never run
  ERROR   session_capture: hosts is empty or missing; the capture flow must be scoped to at least one host
  ERROR   session_capture: capture[0].from 'response_header:x-goog-pageid' is not in the closed vocabulary (cookie_header, page_script:youtube_page_id)
  ERROR   session_capture: capture[0].as_secret 'token' does not name a 'secret'-typed setting this manifest declares
```

Codes: `session_capture_object_missing`, `session_capture_object_without_capability`,
`session_capture_hosts_empty`, `session_capture_unknown_source`,
`session_capture_secret_not_declared`. The last two duplicate what the schema
already enforces for `from` (a closed `enum`) and partially for `as_secret` (a
`settingId` pattern) — the schema cannot express *cross-field* facts like "this
id must name a declared `secret` setting", which is exactly what this rule
adds.

### Reading the output

```
plugins/nebula_music
  ERROR   capabilities: 'webview' requires permission 'webview'   (plugin.json:15)
  WARNING network: permission declared but no network.hosts listed
  INFO    version 0.1.0 is pre-1.0; the plugin API surface is unstable
2 problems (1 error, 1 warning)
```

The trailing count excludes `INFO` — info notes are not problems. Exit code is
`1` if there is at least one error, or at least one warning under `--strict`.

---

## Settings

A setting descriptor tells the host what to render and what type of value to
store. The plugin reads values back through `SwayveSettingsView`:

```dart
final region = context.settings.value<String>('region') ?? 'US';
context.settings.changes.listen((_) => _reconfigure());
```

`value<T>` returns `null` for an absent setting **and** for one that is present
with the wrong type. It never throws: a manifest change must not crash a running
plugin. Read settings fresh rather than caching them at `initialize`, or a user
who changes one keeps getting the old behaviour until they restart the app.

### Descriptor fields

```jsonc
{
  "id": "region",            // ^[a-z][a-z0-9_]*$, unique within the plugin
  "type": "select",          // "string" | "bool" | "int" | "select" | "secret"
  "label": "Region",         // 1..48 chars — the control's visible label
  "description": "…",        // optional, 1..160 chars — helper text below it
  "default": "US",           // optional, must type-match `type`
  "required": false,         // optional, default false
  "options": [               // required iff type == "select", forbidden otherwise
    { "value": "US", "label": "United States" }   // value 1..64, label 1..48
  ],
  "min": 0, "max": 100       // optional, only for type == "int"
}
```

| `type` | Host renders | `default` must be |
|---|---|---|
| `string` | Single-line text field | a JSON string |
| `bool` | Switch | a JSON boolean |
| `int` | Number field, bounded by `min`/`max` if present | a JSON integer |
| `select` | Picker over `options` | one of the `options[].value` strings |
| `secret` | Obscured field; the value goes to the credential store | a JSON string — but never ship a default secret |

### Setting descriptor codes

All errors:

| Code | Rule |
|---|---|
| `setting_duplicate_id` | Setting ids are unique within a plugin |
| `setting_options_required` | `type: select` must declare `options` |
| `setting_options_not_allowed` | Only a `select` may declare `options` |
| `setting_duplicate_option` | Option values are unique within a setting |
| `setting_default_type_mismatch` | `default` must match the declared `type` |
| `setting_default_not_an_option` | A `select` default must be one of its options |
| `setting_range_not_allowed` | Only `type: int` may declare `min`/`max` |
| `setting_range_inverted` | `min` must not exceed `max` |
| `setting_default_out_of_range` | `default` must fall inside `min`..`max` |
| `secret_setting_requires_external_auth` | A `secret` setting needs `external_auth` |

### `secret` is a different storage class

A `type: "secret"` value is written to the **host credential store**, not to
plugin storage, and is never returned to the plugin in plaintext logs. Declaring
one therefore requires the `external_auth` permission:

```
  ERROR   settings: 'api_key' is a secret, which requires the 'external_auth' permission
```

Read it back with `SwayveCredentialStore.readSecret`, not
`SwayveSettingsView.value`. Declaring a `secret` setting also justifies holding
`external_auth` for rule 2, so a plugin whose only credential is a pasted API
key does not trip the over-permissioning warning. The credential story,
including what is only partially built, is in
[permissions.md](permissions.md#credentials).

### The host renders settings UI. Always.

There is no way for a plugin to draw its own settings page, and no plan to add
one. This keeps the settings surface consistent, accessible and themed, and it
means a settings change is a manifest edit rather than a UI review.

---

## See also

- [capabilities.md](capabilities.md) — what each capability commits you to
- [permissions.md](permissions.md) — what each permission grants and withholds
- [versioning.md](versioning.md) — `version` vs `schemaVersion` vs `swayvePluginApi` vs `minimumSwayveVersion`
- [packaging.md](packaging.md) — how the manifest travels inside a `.swayveplugin`
- [`schema/README.md`](../schema/README.md) — the schema's own reference
