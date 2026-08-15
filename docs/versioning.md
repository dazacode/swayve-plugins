# Versioning

Four version numbers appear in every manifest. They move independently, they
mean different things, and checking any one of them alone lets an incompatible
plugin load.

```json
{
  "schemaVersion": 1,
  "version": "0.1.0",
  "swayvePluginApi": 1,
  "minimumSwayveVersion": "0.1.0"
}
```

---

## The four axes

| Field | Type | Answers | Who changes it | Changes when |
|---|---|---|---|---|
| `version` | SemVer | *Which release of this plugin is this?* | The plugin author | Every plugin release |
| `schemaVersion` | integer | *Which manifest format is this file written in?* | This repository | The manifest format changes incompatibly |
| `swayvePluginApi` | integer | *Which SDK API level was this written against?* | This repository | The SDK's provider interfaces change incompatibly |
| `minimumSwayveVersion` | SemVer | *What is the oldest Swayve client this works on?* | The plugin author | The plugin starts relying on newer host behaviour |

Two are integers and two are SemVer, which is not an inconsistency. Integers are
*API levels* — a client either understands level 1 or it does not, and there is
no meaningful "1.2 of the manifest format". SemVer applies to things with
releases: a plugin build, a client build.

### `version`

The plugin's own release number, strict SemVer 2.0.0. It is the version in the
release tag (`youtube_music-v0.1.0`) and in the artefact name
(`youtube_music-0.1.0.swayveplugin`).

A `0.x` version emits an advisory diagnostic at validation:

```
  INFO    version 0.1.0 is pre-1.0; the plugin API surface is unstable
```

It is advisory because pre-1.0 is a legitimate state, not a defect. It exists so
that "we were never told the interfaces might move" is not available later.

Bump it for every published change, including one that changes nothing but a
dependency. Two artefacts with the same version and different bytes is the one
thing that makes the `.sha256` sidecar useless.

### `schemaVersion`

Which manifest *format* the file uses. `1` in v1, and the schema requires
exactly `1` — a manifest declaring `2` is rejected by a v1 host rather than
optimistically parsed.

This is the first thing the host checks, because it determines whether the rest
of the file can be interpreted at all. A future `schemaVersion: 2` means fields
may have been renamed, removed or re-typed; a host that parsed it as if it were
version 1 would not fail, it would misread.

### `swayvePluginApi`

Which SDK API level the plugin's *code* targets — the shape of
`SwayvePluginContext`, the provider interfaces, the models. `1` in v1.

It is separate from `schemaVersion` because the manifest format and the Dart
surface change for different reasons. Adding a new capability changes the schema
(new enum member) without changing any existing interface. Adding a required
parameter to `SwayveSearchProvider.search` changes the API level without
touching the manifest format. Coupling them would force every plugin to
re-declare compatibility with a change that could not affect it.

Mismatch surfaces as `SwayveIncompatibleApiException`, which carries both
numbers:

```dart
final class SwayveIncompatibleApiException extends SwayvePluginException {
  final int requiredApi;   // the level the plugin declared it needs
  final int actualApi;     // the level the host actually implements
}
```

The validator has an equivalent, since a manifest can be checked before any code
runs: `unsupported_plugin_api` (error) when `swayvePluginApi` is above the
build's level, and `unsupported_schema_version` (error) when `schemaVersion` is
not the one the build implements. Both are phrased in the voice the host must
use to a user — the plugin is fine, Swayve is behind.

### `minimumSwayveVersion`

The oldest Swayve client the plugin will run on, as SemVer.

This is the only one of the four the plugin author sets against something
outside their control, and it is the one most often set wrongly. Raise it when
you begin depending on host *behaviour* — a new embed kind, a fixed bug in
timeout handling, a widened playback seam — not when you happen to develop
against a newer build. Raising it needlessly cuts off users for no benefit;
leaving it stale ships a plugin that fails in a way the user cannot act on.

Note that `swayvePluginApi` does not subsume it. An API level says the
*interfaces* match. `minimumSwayveVersion` says the *implementation behind them*
is new enough. A host can support API level 1 for a year while fixing behaviour
a plugin comes to rely on.

---

## Why one check is not enough

Each axis catches a failure the others cannot see:

| Only checked | Slips through |
|---|---|
| `schemaVersion` | A manifest a v1 host can read perfectly, describing a plugin compiled against SDK API level 2. Loads, then throws on the first call into a method that changed shape. |
| `swayvePluginApi` | A plugin whose code matches, running on a client one release too old to have the host behaviour it needs. Loads, then misbehaves subtly — the worst outcome, because nothing errors. |
| `minimumSwayveVersion` | A plugin from a future manifest format, on a host new enough by version but unable to interpret fields it has never seen. |
| `version` | Everything. A plugin's own version says nothing about compatibility with anything. |

The pattern is that a single check produces a plugin that *loads* and then fails
later, at a point where the user has no idea what went wrong. Checking all four
up front converts every one of those into a clear rejection before the plugin
runs a line of code.

---

## The compatibility check order

Checked in this order, at the `checkCompatibility` stage of the
[lifecycle](architecture.md#lifecycle). The order is part of the contract,
because it determines which reason the user is shown when more than one thing
is wrong — and the first failure is always the most fundamental one.

| # | Check | Rejection reason shown |
|---|---|---|
| 1 | `schemaVersion` is understood by this host | *"This plugin was made for a newer version of Swayve."* |
| 2 | `swayvePluginApi` ≤ the host's API level | *"YouTube Music requires a newer version of Swayve."* |
| 3 | `minimumSwayveVersion` ≤ the host's version | *"YouTube Music requires Swayve 1.2 or newer."* |
| 4 | `platforms` contains the host platform | *"YouTube Music is not available on this device."* |
| 5 | `runtime` is supported on this host platform | *"YouTube Music is not supported on this device."* |

Why this order and not another:

- **`schemaVersion` first** because until it passes, no other field can be
  trusted to mean what the host thinks it means. Reading
  `minimumSwayveVersion` out of a format you do not understand is guessing.
- **API level before client version** because the API level is the coarser,
  more certain signal. If the interfaces do not match, the client version is
  irrelevant.
- **Platform last** because platform availability is the most specific and most
  actionable message, and it would be misleading to show it when the real
  problem is that the app is out of date. A user told *"not available on this
  device"* will stop trying; a user told *"requires a newer version"* will
  update.

Checks 4 and 5 are distinct: 4 asks whether the plugin claims this platform at
all, 5 asks whether this *kind* of plugin can run here — which is where
`bundled` on iOS is refused even if the manifest somehow reached a device. See
[platforms.md](platforms.md).

---

## Graceful rejection

An incompatible plugin produces one sentence the user can act on. Never a stack
trace, never an error code, never a crash, and never silence.

```
YouTube Music requires a newer version of Swayve.
```

The rules the host follows:

- **Name the plugin**, using the manifest's `name`. "A plugin" is not
  actionable when three are installed.
- **State the constraint, not the mechanism.** "Requires a newer version of
  Swayve" — not "swayvePluginApi 2 > host 1". The developer-facing detail goes
  to the log, where the developer is.
- **Say what would fix it** where something would: update the app, or nothing
  in the platform case.
- **Keep the plugin listed** in settings with its reason, rather than making it
  vanish. A plugin that disappears silently is a support ticket.
- **Never offer to load anyway.** A compatibility rejection is a decision, not
  a warning. The one place this matters most is integrity failure, which is not
  a compatibility check at all and is never overridable.

Contrast with a *runtime* failure, which is a different state and a different
message: a plugin that loaded and then threw shows
*"YouTube Music — Temporarily unavailable"* and stays loaded in `degraded`. The
distinction is real — "will never work here" versus "did not work just now" —
and the host should not blur it.

---

## Changing versions in this repository

| Change | Bump |
|---|---|
| A plugin's behaviour or dependencies | that plugin's `version` |
| A new optional manifest field | nothing — additive fields do not break readers |
| A renamed, removed or re-typed manifest field | `schemaVersion` |
| A new capability in the vocabulary | `schemaVersion` (the enum widened), and the SDK, docs and validator together |
| A new provider interface, or a new optional method | nothing — existing plugins still satisfy their interfaces |
| A changed signature on an existing provider interface | `swayvePluginApi` |
| Host behaviour a plugin can newly rely on | nothing here; plugins raise their own `minimumSwayveVersion` |

Adding a capability requires the docs, the SDK and the validator to move in the
same change. A vocabulary that is documented but not validated, or validated but
not documented, is worse than not having the capability.

---

## See also

- [plugin-manifest.md](plugin-manifest.md) — the fields these numbers live in
- [architecture.md](architecture.md#lifecycle) — where the compatibility check sits
- [publishing.md](publishing.md) — tags, and pinning the SDK to one
- [host-integration.md](host-integration.md) — the host side of these checks
