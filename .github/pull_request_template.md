<!--
Thanks for contributing to swayve-plugins.

The checklist below is the acceptance bar from CONTRIBUTING.md, not a formality:
a PR that cannot tick these will not be merged. Delete sections that genuinely
do not apply and say why.
-->

## What this changes

<!-- One paragraph. What behaviour is different after this PR, for whom? -->

## Why

<!-- The problem being solved. Link the issue or plugin proposal: Fixes #123 -->

## Type of change

- [ ] New plugin
- [ ] Change to an existing plugin
- [ ] SDK (`packages/swayve_plugin_sdk`) change
- [ ] Tooling / schema change (`tools/`, `lib/`, `schema/`)
- [ ] Docs only
- [ ] CI / repository furniture

## Acceptance checklist

**Correctness**

- [ ] `dart run tools/validate_plugin.dart --all --strict` passes with zero errors *and zero warnings*.
- [ ] `dart format --output=none --set-exit-if-changed .` is clean in every package I touched.
- [ ] `dart analyze --fatal-infos` reports nothing in every package I touched.
- [ ] Tests are added or updated for this change, and the full suite passes locally.
- [ ] The change works on the platforms the manifest declares (say which you actually ran on).

**Contract**

- [ ] No host-side, plugin-specific branching was introduced anywhere — no `if (plugin.id == '…')`, no provider name leaking into host logic. Everything goes through the SDK's provider interfaces.
- [ ] Every permission declared in `plugin.json` is implied by a declared capability, and each one is justified below.
- [ ] Only the existing closed capability/permission vocabulary is used. (Adding a term is a schema + SDK + validator + docs change and needs its own proposal.)
- [ ] `network.hosts` lists every host this plugin actually contacts, and nothing it does not.
- [ ] No secret is ever written to plugin storage or to a log — secrets live in the host credential store only.
- [ ] Public SDK members I added or changed have doc comments describing the **contract**.
- [ ] `version` in `plugin.json` / `pubspec.yaml` and the `CHANGELOG.md` entry were updated if this is a released change.
- [ ] The SDK still has zero runtime dependencies and no `flutter`, `dart:io` or `dart:ui` import.

**Compatibility**

- [ ] This is not a breaking change to `swayvePluginApi`, the manifest schema, or the `.swayveplugin` format — or, if it is, it is called out below with the migration.
- [ ] Packaging is still deterministic: packaging the same input twice produces a byte-identical bundle.

### Permission justification

<!--
One line per permission in the manifest, naming the capability that requires it
and the user-facing feature it serves. Write "none" if the plugin declares no
permissions. Over-permissioning is a blocking review comment.
-->

| permission | required by capability | why |
| --- | --- | --- |
|  |  |  |

## How this was tested

<!-- Commands you ran, platforms you ran them on, and what you observed. -->

## Breaking changes / migration

<!-- "None", or exactly what a consumer must do. -->
