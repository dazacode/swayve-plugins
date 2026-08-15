# Packaging

A `.swayveplugin` is a deterministic ZIP archive carrying a plugin, its assets,
its licences, a hash manifest and an optional signature.

```bash
dart run tools/package_plugin.dart plugins/youtube_music --out dist
dart run tools/verify_package.dart dist/youtube_music-0.1.0.swayveplugin
```

`package_plugin` validates before it packages and refuses to produce an archive
from a manifest that fails. There is no `--force`.

---

## Why not encryption

The instinct is to encrypt the archive so nobody can read the plugin. It does
not work, and pretending otherwise buys a false sense of safety.

**Code that runs on the user's device cannot be secret from the user.** To
execute a plugin, Swayve must decrypt it, which means Swayve must hold the key,
which means the key is on the device the attacker owns. Every "encrypted plugin"
scheme reduces to obfuscation with extra steps, and obfuscation that is
mistaken for security is worse than no obfuscation, because it changes what
people are willing to put inside.

So the format optimises for the two properties that *are* achievable:

| Goal | Mechanism | What it actually guarantees |
|---|---|---|
| **Integrity** | SHA-256 per file + a canonical bundle digest | The bytes you run are the bytes that were packaged. Any modification — corruption in transit, a tampered mirror, a partial write — is detected before load. |
| **Identity** | Detached Ed25519 signature over the digest | The bundle came from the holder of a known key. Not "this plugin is safe", but "this plugin is from who it claims". |

Neither hides anything, and neither is meant to. Confidentiality of plugin
*source* is not a goal of this project — the reference plugins are Apache-2.0 in
a public repository. What matters is that a user who installs "YouTube Music
0.1.0" gets the artefact the author published, unmodified, and can be told when
they have not.

The third leg is **explicit permissions**: even a correctly signed plugin only
gets the facilities its manifest declares, which the user can read.

---

## Archive layout

```
youtube_music-0.1.0.swayveplugin
├── plugin.json          # byte-identical to the source manifest
├── integrity.json       # sha256 of every other file + canonical bundle digest
├── signature.json       # detached signature over the digest (may be unsigned)
├── payload/             # entrypoint payload
├── assets/              # icon and any declared assets
└── licenses/            # LICENSE + third-party notices — required, non-empty
```

| Entry | Required | Notes |
|---|---|---|
| `plugin.json` | yes | Byte-identical to the source file. The packager does not rewrite, reformat or minify it — a reader can diff the archive's manifest against the repository's. |
| `integrity.json` | yes | Generated. Never hand-edited. |
| `signature.json` | yes | Always present, even when unsigned — its absence would be ambiguous, while `{"signed": false}` is a statement. |
| `payload/` | yes | What the host or the build needs. See below. |
| `assets/` | if declared | Everything referenced by `icon` and any other asset path. |
| `licenses/` | yes, non-empty | The plugin's licence plus notices for anything it bundles. Enforced twice: `licenses_empty` at packaging, and again by the verifier on the archive. |

The verifier requires `plugin.json`, `integrity.json`, `signature.json` and at
least one `licenses/` entry (`bundle_missing_member`, `licenses_empty`).

### What is in `payload/`

For a `compiled` plugin the packager copies:

```
payload/README.md          the plugin's README, so a bundle is self-describing
payload/pubspec.yaml       what it was built from
payload/lib/**             the plugin's Dart source
payload/**                 anything in a source `payload/` directory, verbatim
```

The archive is a **distribution record**, not an executable: a `compiled`
plugin's code reaches a device inside the app binary, not out of this file.
Carrying the source anyway is what makes a bundle reviewable and reproducible
against a checkout.

For a `bundled` plugin, `payload/` is the declarative payload the host
interprets — never executable Dart. See [platforms.md](platforms.md).

README and `pubspec.yaml` live under `payload/` rather than at the archive root
because the root is pinned to exactly five names.

The archive filename is `<entrypoint>-<version>.swayveplugin`, derived from the
manifest — which is why the directory name must equal `entrypoint`
([rule 7](plugin-manifest.md#7-directory-name-must-equal-entrypoint--error)). A
mismatch between the filename and the manifest is a `bundle_name_mismatch`
warning at verification. A sibling `<entrypoint>-<version>.sha256` is written
next to it in `sha256sum` format — `<hex>  <filename>` — so `sha256sum -c` works
directly.

Required files in the **source** directory before packaging: `plugin.json`,
`README.md`, `pubspec.yaml`, and the directories `lib/`, `licenses/` (non-empty)
and `test/`. A plugin with no tests does not package (`missing_required_file`).
A declared `icon` whose file does not exist fails too (`icon_file_missing`).

Dotfiles never travel: any path segment beginning with `.` — `.dart_tool`,
`.DS_Store`, `.packages` — is skipped during collection.

---

## `integrity.json`

```json
{
  "algorithm": "sha256",
  "files": {
    "plugin.json": "9f2c8a1d…",
    "assets/icon.svg": "4b7e0c33…",
    "licenses/LICENSE": "a1c9f0de…"
  },
  "digest": "e3b0c44298fc1c149afbf4c8996fb924…",
  "generator": "swayve_plugin_tools/0.1.0"
}
```

`files` maps every archive path **except** `integrity.json` and
`signature.json` to the lowercase hex SHA-256 of its bytes.

`digest` is the SHA-256 of a canonical string built by concatenating, for every
file in `files`:

```
"<path>\n<sha256>\n"
```

with paths sorted **byte-wise ascending** and `integrity.json` /
`signature.json` excluded. Byte-wise, not locale-aware: sorting must not depend
on the machine that ran the packager.

Two consequences worth stating plainly:

- Changing any file changes the digest, so a single value identifies the whole
  bundle.
- The digest is computed over paths *and* hashes, so renaming a file changes it
  even if no bytes changed. Reordering the archive does not, since the sort is
  canonical.

`generator` records which tool version produced the archive. It is
informational, but it is the first thing to look at when two builds of the same
input disagree.

---

## `signature.json`

Unsigned:

```json
{ "signed": false, "algorithm": "none" }
```

Signed:

```json
{
  "signed": true,
  "algorithm": "ed25519",
  "publicKey": "MCowBQYDK2VwAyEA…",
  "signature": "3q2+7wUB…",
  "keyId": "9f2c8a1d",
  "digest": "e3b0c44298fc1c149afbf4c8996fb924…"
}
```

The signature is **detached** and covers `integrity.json`'s `digest` — precisely,
the **ASCII bytes of the lowercase hex digest string**, not the raw 32-byte hash
and not the archive bytes.

Signing the text rather than the raw hash keeps `signature.json`
self-describing: what was signed is literally the string in its own `digest`
field, so a verifier needs no out-of-band knowledge of an encoding to reproduce
the signed payload. Signing a 64-character string rather than a multi-megabyte
file also means verification is cheap, and that the signature survives any
future compression change that does not alter content.

Signing is **live**, not stubbed: `package_plugin --key` produces a real Ed25519
signature, and `verify_package --pubkey` really verifies it. The tool refuses to
pretend — if a build could not sign, `--key` fails with `signing_unavailable`
rather than quietly emitting an unsigned bundle. A key file may be 32 raw bytes,
64 raw bytes (seed followed by public key), 64 hex characters, or base64;
trailing whitespace is ignored. A key that decodes to anything else is
`signing_key_invalid`.

`keyId` is the first 8 hex characters of the key fingerprint — a human handle
for "which key", not a security boundary. `publicKey` is carried in the file for
convenience; **carrying a key is not trusting a key.** A verifier that accepts
the embedded key without checking it against an expected one has verified
nothing except internal consistency, which is why `verify_package` requires an
explicit `--pubkey` to make a trust claim:

```bash
# Checks hashes, digest and structure. An unsigned bundle is an INFO note.
dart run tools/verify_package.dart dist/youtube_music-0.1.0.swayveplugin

# Additionally checks the signature against a key you decided to trust.
# --pubkey takes a file or a base64 literal, and must decode to 32 bytes.
dart run tools/verify_package.dart dist/youtube_music-0.1.0.swayveplugin \
  --pubkey keys/swayve.pub

# Fail an unsigned bundle outright rather than noting it.
dart run tools/verify_package.dart dist/youtube_music-0.1.0.swayveplugin \
  --require-signature

# Test path containment against the directory you will actually unpack into.
dart run tools/verify_package.dart dist/youtube_music-0.1.0.swayveplugin \
  --dest /var/swayve/plugins/pending
```

`signature_absent` is an **info** note by default and an **error** when either
`--require-signature` or `--pubkey` is given — asking about a key and getting no
signature is a failure, not a remark. `--dest` defaults to
`/var/swayve/plugins/pending`; it is only used as the root that entry paths are
resolved against, and nothing is extracted.

Sign with:

```bash
dart run tools/package_plugin.dart plugins/youtube_music --key path/to/ed25519.key
```

**Key distribution is future work.** There is no key server, no trust store, no
revocation list and no pinned first-party key in v1. Signing is available;
deciding *which* keys matter is not yet answered. See
[publishing.md](publishing.md).

---

## Determinism

Packaging the same input twice must produce a **byte-identical** archive. This
is a required test in the tool suite, not an aspiration.

| Rule | Reason |
|---|---|
| Entries sorted by path, byte-wise ascending over UTF-8 | Filesystem enumeration order differs across platforms and even across runs. Byte-wise, not `String.compareTo`, which orders by UTF-16 code unit and diverges above the BMP. |
| Fixed timestamp `1980-01-01T00:00:00Z` on every entry | Modification times are the single largest source of accidental non-determinism. `1980-01-01` is the earliest the ZIP format can represent. |
| Fixed compression level (deflate 9) | Different levels produce different bytes from identical input, and pinning it means a future default change cannot alter existing bundles. |
| Fixed entry mode `0644` | No execute bit, no ownership, nothing about the machine that built it. |
| LF-normalised text files | Otherwise a Windows checkout and a Linux checkout of the same repository produce different archives. Applies to `.dart`, `.json`, `.md`, `.txt`, `.yaml`, `.yml`, `.svg`, `.html`, `.css`, `.js`, `.xml`, `.toml`, `.cfg`, `.ini` and extensionless `LICENSE`/`NOTICE`/`COPYING`/`AUTHORS`/`CHANGELOG` — and is skipped for any of them that turns out to contain a NUL byte. |
| One JSON encoding | `integrity.json` and `signature.json` are written with a two-space indent, LF endings and one trailing newline. Anything that varies between runs, map iteration order included, is settled before encoding. |

The payoff is that determinism turns "is this the official build?" into a
question anyone can answer with a checkout and a command, rather than a question
only the publisher can answer. It also makes the `.sha256` sidecar meaningful:
two people packaging the same tag should be able to compare hashes and get the
same answer.

If you get a non-reproducible archive, the cause is almost always a file that
differs between checkouts — a generated file, a line-ending difference in an
asset the normaliser treats as binary, or an untracked file being picked up.

---

## Extraction safety

A ZIP archive is untrusted input. Every unpacker in this project — the verifier,
the host loader, and anything a contributor writes — must reject an entry that:

| Condition | Cap | Diagnostic code |
|---|---|---|
| The file is not a readable ZIP | — | `archive_unreadable` |
| The archive has no entries | — | `archive_empty` |
| Absolute path (`/etc/passwd`) | rejected | `entry_absolute_path` |
| Contains `..` in any segment | rejected | `entry_parent_traversal` |
| Contains a backslash | rejected | `entry_backslash` |
| Carries a drive letter or UNC prefix | rejected | `entry_drive_letter` |
| Contains a NUL or other control character | rejected | `entry_control_character` |
| Is a symbolic link | rejected | `entry_symlink` |
| Two entries normalise to the same destination | rejected | `entry_duplicate` |
| Exceeds the per-file size cap | 64 MiB | `entry_too_large` |
| Exceeds the total uncompressed cap | 256 MiB | `archive_too_large` |
| Exceeds the entry count cap | 10,000 entries | `archive_too_many_entries` |

And the rule that catches what the list above misses — `entry_escapes_root`:

> **Every resolved path must stay inside the destination root — verified after
> normalisation, not before.**

Checking the raw entry name for `..` is not sufficient. Percent-encoding,
alternate separators, redundant segments, unicode normalisation and symlinked
intermediate directories all produce names that look safe and resolve outside
the root. Normalise the joined path, resolve it, and compare it to the resolved
root. If it is not a descendant, reject the whole archive — not just the entry,
because an archive containing one traversal attempt is not an archive you want
the rest of.

The size and count caps exist for zip bombs: a 1 MB archive can expand to
terabytes, and an unbounded extractor will fill the user's disk before anything
else notices. Enforce them **during** extraction against the running total, not
against the header-declared sizes, which the archive controls.

The same path rules are enforced earlier, on the manifest's path-valued fields
([rule 10](plugin-manifest.md#10-path-safety--error)). Both checks are needed:
the manifest check catches an author's mistake at review time, the extraction
check catches an attacker at load time.

`verify_package` runs extraction safety **first**, before it looks at the
manifest, integrity or the signature. An archive that is unsafe to unpack is not
one whose contents are worth reading.

### Integrity and signature codes

| Code | Meaning |
|---|---|
| `integrity_malformed` | `integrity.json` missing, malformed, or the wrong shape |
| `integrity_algorithm_unsupported` | It names a digest algorithm this build does not implement |
| `integrity_file_missing` | A file it lists is not in the archive |
| `integrity_file_unlisted` | A file in the archive is not listed in it |
| `integrity_hash_mismatch` | A file's sha256 differs from the one recorded |
| `integrity_digest_mismatch` | The recomputed bundle digest differs from the recorded one |
| `signature_malformed` | `signature.json` missing, malformed, or the wrong shape |
| `signature_absent` | The bundle carries no signature (info, or error under `--require-signature`/`--pubkey`) |
| `signature_digest_mismatch` | The signature covers a digest other than this bundle's |
| `signature_invalid` | The signature does not verify against the public key |
| `signature_key_mismatch` | The bundle's key is not the one `--pubkey` asked for |
| `bundle_missing_member` | A required archive member is absent |
| `bundle_name_mismatch` | The filename does not match `<entrypoint>-<version>.swayveplugin` (warning) |

`integrity_file_unlisted` matters as much as `integrity_file_missing`: a hash
manifest that only checks the files it knows about would let an attacker *add*
one.

---

## What verification proves — and what it does not

| `verify_package` says | It means | It does not mean |
|---|---|---|
| Hashes match | Every file is byte-identical to what was packaged | The plugin is well-behaved |
| Digest matches | No file was added, removed or renamed | The plugin is from anyone in particular |
| Signature valid against `--pubkey` | The holder of that key packaged this | That key belongs to who you think |
| Structure safe | Extraction will not escape the destination | The plugin's network calls are safe |

Verification is about the artefact. Behaviour is governed by
[permissions](permissions.md) and by review; the threat model is in
[SECURITY.md](../SECURITY.md).

---

## See also

- [platforms.md](platforms.md) — why a `bundled` archive carries no executable code
- [publishing.md](publishing.md) — how archives reach users
- [plugin-manifest.md](plugin-manifest.md) — what has to be true before packaging starts
