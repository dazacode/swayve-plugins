# Swayve plugin manifest schema

`swayve-plugin.schema.json` is the published description of a plugin's
`plugin.json`.

| | |
|---|---|
| `$id` | `https://swayve.app/schema/swayve-plugin.schema.json` |
| Draft | `https://json-schema.org/draft/2020-12/schema` |
| `schemaVersion` | `5` (`1`, `2`, `3` and `4` also validate) |

Point an editor at it to get completion and inline errors while writing a
manifest:

```json
{
  "$schema": "https://swayve.app/schema/swayve-plugin.schema.json"
}
```

The schema does **not** appear in a manifest as a `$schema` key — the manifest's
own property set is closed, so editors should be configured to associate
`plugin.json` with this file rather than the file declaring itself.

## What the schema decides, and what it cannot

Every object in the manifest sets `additionalProperties: false`. A field this
schema does not name is a rejected manifest, not an ignored key. That is
deliberate: a typo in `capabilities` must fail loudly rather than silently
disable a capability.

The schema covers **structure**: which fields exist, their types, their closed
vocabularies, their patterns and their length and range bounds.

It cannot express relationships **between** fields — that a capability implies a
permission, that `runtime: bundled` and the `ios` platform are incompatible,
that a plugin's directory name must equal its `entrypoint`. Those rules live in
`swayve_plugin_tools` and are listed below.

## Reusable definitions

Everything shared lives under `$defs` so a manifest constraint is stated once:

| `$def` | What it is |
|---|---|
| `semver` | Strict SemVer 2.0.0, the regex published at semver.org |
| `pluginId` | Reverse-DNS id, three or more lowercase segments |
| `httpUrl` | An `http`/`https` URL |
| `email` | An email address |
| `assetPath` | A relative path under `assets/`, ending `.png` or `.svg` |
| `hostPattern` | A hostname, optionally with one leading `*.` label |
| `keyword` | A lowercase discovery keyword |
| `settingId` | A setting identifier |
| `capability` | The closed capability vocabulary |
| `permission` | The closed permission vocabulary |
| `platform` | `android` · `ios` · `windows` · `macos` · `linux` |
| `runtime` | `compiled` · `bundled` |
| `settingType` | `string` · `bool` · `int` · `select` · `secret` |
| `author` | `{ name, url?, email? }` |
| `media` | `{ streamable?, downloadable?, offlineCache? }` |
| `network` | `{ hosts }` |
| `sessionCaptureSource` | The closed `session_capture.capture[].from` vocabulary |
| `sessionCaptureEntry` | `{ from, as_secret }` |
| `sessionCapture` | `{ hosts, capture }` |
| `timeouts` | `{ requestMs?, operationMs? }` |
| `settingOption` | `{ value, label }` |
| `settingDescriptor` | One host-rendered setting |

## Checks that live in the validator, not the schema

`dart run tools/validate_plugin.dart <plugin directory>` runs the schema's
structure **and** the rules below. Each diagnostic carries a stable machine
code, visible with `--json`.

### Cross-field rules

| Code | Severity | Rule |
|---|---|---|
| `capability_requires_permission` | error | A capability that cannot function without a permission, declared without it |
| `capability_expects_network` | info | A capability that usually reaches an external service, declared without `network` |
| `permission_not_implied` | warning | A permission no declared capability needs is over-permissioning |
| `downloadable_requires_streaming` | error | `media.downloadable` needs the `streaming` capability |
| `bundled_runtime_not_allowed_on_ios` | error | `runtime: bundled` cannot list the `ios` platform |
| `network_permission_without_hosts` | warning | The `network` permission with nothing in `network.hosts` |
| `entrypoint_id_mismatch` | warning | `entrypoint` should equal the last segment of `id` |
| `directory_name_mismatch` | error | The plugin's directory name must equal `entrypoint` |
| `first_party_author_mismatch` | error | `app.swayve.plugins.*` requires `author.name` of `Swayve` |
| `prerelease_api_unstable` | info | A `0.x` version means the surface may still move |
| `unsafe_relative_path` | error | A path-valued field that is absolute, escaping or malformed |
| `source_declares_no_content_types` | info | `search` is declared but `source.contentTypes` names nothing to offer it under |
| `source_without_reachable_capability` | info | A `source` on a plugin declaring neither `search` nor `catalog` |
| `session_capture_object_missing` | error | `session_capture` capability declared with no `session_capture` object |
| `session_capture_object_without_capability` | info | A `session_capture` object declared without the capability |
| `session_capture_hosts_empty` | error | `session_capture.hosts` is empty or missing |
| `session_capture_unknown_source` | error | A `session_capture.capture[].from` outside the closed vocabulary |
| `session_capture_secret_not_declared` | error | A `session_capture.capture[].as_secret` naming no declared `secret` setting |
| `capability_requires_capability` | error | A capability that cannot function without another declared capability, declared without it |

#### Capabilities and permissions

Three capabilities are **structurally** unusable without one or more
permissions, because the capability and the permission(s) describe the same
act. Declaring a capability without every permission it requires describes a
plugin that cannot do what it says it does, so each missing one is an error:

| Capability | Required permission(s) |
|---|---|
| `webview` | `webview` |
| `authentication` | `external_auth` |
| `session_capture` | `webview` and `external_auth` |

Two more capabilities are structurally unusable without *another declared
capability* rather than a permission, checked by the separate
`capability_requires_capability` rule:

| Capability | Required capability |
|---|---|
| `personal_library` | `authentication` |
| `personal_library_push` | `personal_library` |

The remaining ten — `search` `catalog` `streaming` `metadata` `lyrics`
`scrobbling` `artwork` `playlist_read` `artist_activity` `personal_library`
— *usually* reach an external service (`personal_library_push`,
`metadata_search`, `radio` and `visuals` are the eleventh through
fourteenth), but not always. A `search` provider can perfectly well serve a
catalogue that ships inside the plugin. Whether a plugin opens a connection
is not decidable from its manifest, so their absence of `network` is an
**info note** (`capability_expects_network`) and never a failure. A plugin
that is honestly offline declares `permissions: []` and passes `--strict`
clean.

Under-declaration is caught where the answer is actually knowable — at runtime.
`context.http` throws `SwayvePermissionDeniedException` unless `network` is
declared, and `FakeSwayvePluginContext` reproduces that in the plugin's own
tests, so a plugin that really does need the network fails its own suite long
before a user sees it.

Over-declaration is the direction that costs a user trust, and it stays a
warning: `permission_not_implied` fires for any permission that no declared
capability justifies. `local_plugin_storage` and `clipboard` are host facilities
rather than provider interfaces, so holding either is never over-permissioning,
and holding `external_auth` is likewise justified by declaring a `secret`
setting.

### Setting descriptor rules

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

### Compatibility

| Code | Rule |
|---|---|
| `unsupported_schema_version` | `schemaVersion` is not the one this build implements |
| `unsupported_plugin_api` | `swayvePluginApi` is above this build's API level |

Both are phrased the way the host must phrase them to a user: the plugin is
fine, Swayve is behind.

### One check the schema does not carry

`name` must contain no emoji. That is enforced in the validator
(`field_emoji`) rather than as a `pattern`, because a regex over the emoji
planes is far harder to read than the rule it encodes.

## Keeping this file honest

The validator does not consume this JSON at runtime — it runs an equivalent
description written in Dart, which is what makes precise, author-facing messages
possible. `test/schema_sync_test.dart` walks both descriptions in step and fails
if they disagree about a single field name, type, pattern, bound or vocabulary
entry. Change one and the test will tell you to change the other.

## Changing the schema

`schemaVersion` is `7`, having moved from `6` to `7` when the `radio` and
`visuals` capabilities were added (from `5` to `6` when `metadata_search`
was added, from `4` to `5` when `personal_library_push` was added, from `3`
to `4` when `session_capture` was added, from `2` to `3` when
`personal_library` was added, and from `1` to `2` when `artist_activity` was
added before that). The check in `checkCompatibility()` only rejects a
`schemaVersion` *newer* than the build understands — a `schemaVersion: 1`
manifest keeps validating on a build that implements `7`, because the format
has so far only ever widened.

* Adding an **optional** field is a minor change: add it to the schema, to
  `lib/src/schema_spec.dart`, and to `docs/plugin-manifest.md`.
* Adding a **capability** or **permission** is a vocabulary change and lands
  together with the SDK's provider interface, the validator's implication table,
  and the documentation. Never on its own.
* Anything that would reject a manifest v1 accepts is a `schemaVersion` bump,
  and the host must keep reading version 1 manifests — see
  `checkCompatibility()` in `lib/src/manifest_rules.dart`.
