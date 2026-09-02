# Publishing

How a plugin release leaves this repository, what a tag triggers, and what does
not exist yet.

> **This describes `release.yml` as it worked while plugins lived in this
> repository.** They do not any more, so a `<plugin>-v<semver>` tag pushed
> here has nothing under `plugins/` to find and the workflow fails harmlessly
> with "directory does not exist" rather than publishing anything. Until a
> plugin repository grows an equivalent tag-triggered workflow of its own,
> package and publish a bundle by hand with the tools below, run from a
> `swayve-plugins` checkout against a plugin directory beside it. An
> `sdk-v<semver>` tag pushed here is unaffected — the SDK itself still lives
> in `packages/swayve_plugin_sdk`, in this repository.

---

## Tag format

```
<entrypoint>-v<semver>
```

| Example | Means |
|---|---|
| `youtube_music-v0.1.0` | version `0.1.0` of `plugins/youtube_music` |
| `example-v0.1.0` | version `0.1.0` of `plugins/example` |
| `sdk-v0.1.0` | version `0.1.0` of `packages/swayve_plugin_sdk` |

The `entrypoint` prefix is what makes a monorepo of independently versioned
plugins workable: a bare `v0.1.0` would be ambiguous the moment there is a
second plugin, and renaming tags after the fact is not an option. The `v` before
the number keeps the tag from colliding with a branch named after a version.

The version in the tag **must equal** the `version` field in that plugin's
`plugin.json`. Release CI checks this and fails the release if they disagree —
a tag that claims a version the manifest does not is how a user ends up with an
artefact whose contents contradict its name.

## Cutting a release

```bash
# 1. Bump the version in the manifest, and add a CHANGELOG entry.
#    (in your plugin's checkout) my_plugin/plugin.json  →  "version": "0.2.0"

# 2. Prove it green locally, exactly as CI will.
(cd ../my_plugin && dart format . && dart analyze)
dart run tools/validate_plugin.dart ../my_plugin --strict
(cd ../my_plugin && dart test)

# 3. Build the artefacts you are about to publish, and verify them.
dart run tools/package_plugin.dart ../my_plugin --out dist
dart run tools/verify_package.dart dist/youtube_music-0.2.0.swayveplugin

# 4. Merge to main, then tag the merge commit.
git tag youtube_music-v0.2.0
git push origin youtube_music-v0.2.0
```

Step 3 is not redundant with CI. Building locally first means a packaging
failure costs you a minute rather than a tag you have to delete.

## Release assets

Every plugin release publishes exactly two files:

| Asset | Contents |
|---|---|
| `<entrypoint>-<version>.swayveplugin` | The deterministic archive. See [packaging.md](packaging.md). |
| `<entrypoint>-<version>.sha256` | The SHA-256 of the archive file, so the download can be checked before it is opened. |

Note the asset names carry no `v` — the tag is `youtube_music-v0.2.0`, the
artefact is `youtube_music-0.2.0.swayveplugin`. The artefact name is derived
from the manifest by the packager, and the manifest holds a bare SemVer.

Signed releases additionally carry a populated `signature.json` **inside** the
archive rather than as a separate asset; the signature is detached from the
files but not from the bundle. See
[packaging.md](packaging.md#signaturejson).

## What CI does on a tag

`.github/workflows/release.yml` triggers on tags matching `*-v*.*.*`:

1. **Parse the tag** and resolve the plugin from its prefix, failing if no such
   directory exists under `plugins/`.
2. **Check the version** in `plugin.json` against the tag suffix. Mismatch fails
   the release before anything is built.
3. **Validate** the plugin being released with `--strict`, then validate *every*
   plugin with `--strict` — a release is a bad moment to discover a sibling
   broke.
4. **Test** every package's suite, each in its own directory.
5. **Package** with `package_plugin.dart`, which validates again on its own
   account and refuses to package a failing manifest.
6. **Verify** the produced archive with `verify_package.dart` — extraction
   safety, then integrity, then signature — because publishing an artefact
   nobody checked is how a corrupt build reaches users.
7. **Generate and cross-check** the SHA-256, so the sidecar cannot disagree with
   the file beside it.
8. **Compose release notes** and **publish** a GitHub Release for the tag,
   attaching the `.swayveplugin` and the `.sha256`.

The release job builds from the tag, never from a local `dist/`. `dist/` is a
development convenience and is gitignored.

The `validate` and `test` workflows run on every push and pull request; they are
the same checks minus packaging and publishing. Their badges are at the top of
the [README](../README.md).

## Consuming a release

A plugin's SDK dependency should be pinned to a tag rather than a branch once
you are publishing:

```yaml
dependencies:
  swayve_plugin_sdk:
    git:
      url: https://github.com/dazacode/swayve-plugins.git
      path: packages/swayve_plugin_sdk
      ref: sdk-v0.1.0        # not `main`
```

`ref: main` is fine while you are developing and is a liability in a release:
it makes your published plugin's behaviour depend on when someone happened to
resolve it.

## What does not exist yet

Being precise about the boundary, because the gap between "specified" and
"shipped" is wide here.

| Piece | Status |
|---|---|
| **GitHub Releases as the distribution channel** | This is the channel. Not an interim measure with a deadline — the position for now. |
| **`registry.json`** | **Future work.** There is no index of available plugins, no discovery endpoint, no in-app plugin browser, and no format for one yet. Do not build against a registry; it does not exist. |
| **In-app installation of a `bundled` plugin** | **Not implemented.** The client has no plugin loader at all — see [host-integration.md](host-integration.md). Today a release is an artefact a developer can download and verify, not something a user can install. |
| **Key distribution and a trust store** | **Future work.** Signing itself is live — `package_plugin --key` produces a real Ed25519 signature and `verify_package --pubkey` really verifies it. What is missing is any answer to *which key*: no key server, no trust store, no pinned first-party key. A signed bundle today proves internal consistency and that *some* key signed it, which is only useful if you already know which key to expect — hence `--pubkey` being required before the tool makes a trust claim at all. |
| **Signature revocation** | **Future work.** There is no revocation list and no mechanism to distribute one. |
| **Automatic updates** | **Not implemented**, and gated behind everything above. |
| **Publishing to pub.dev** | **Not planned.** The SDK is consumed as a git dependency; see [development.md](development.md#how-the-sdk-is-consumed). |

### Why a registry is deliberately last

A registry is the piece that turns a set of artefacts into an ecosystem, and it
is also the piece that cannot be retrofitted safely. It needs the trust story
(which keys?), the update story (how is a stale plugin retired?), the review
story (what got it listed?) and the revocation story (what happens when one goes
bad?) answered first. Shipping an index before those exist would create exactly
the expectation — "if it is listed, it is safe" — that nothing in the system
would be able to honour.

So the order is: format, tooling, verification, host loader, trust, then
registry. This repository has the first three.

---

## See also

- [versioning.md](versioning.md) — what a version number in a tag actually promises
- [packaging.md](packaging.md) — what is inside the asset you are publishing
- [platforms.md](platforms.md) — why a released `bundled` archive carries no code
- [CONTRIBUTING.md](../CONTRIBUTING.md) — getting a plugin accepted before it can be released
