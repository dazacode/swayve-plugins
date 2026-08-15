# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security report.**

Use GitHub's private vulnerability reporting on this repository:

> **https://github.com/dazacode/swayve-plugins/security/advisories/new**

That channel is private between you and the maintainers, supports attachments,
and becomes the advisory if the report is confirmed.

<!-- MAINTAINER: replace the line below with a monitored security contact address. -->
If you cannot use GitHub advisories, contact: **&lt;security contact not yet
published — see the GitHub advisory link above&gt;**

### What to include

- What you found, and where — file, function, manifest field, or tool.
- How to reproduce it. A failing test, a crafted `plugin.json`, or a
  `.swayveplugin` fixture is worth more than a description.
- What an attacker gains. "Reads another plugin's credentials" and "prints a
  confusing error" need very different responses.
- Whether it is already public anywhere.

### What to expect

| | |
|---|---|
| Acknowledgement | Within 5 working days |
| Initial assessment | Within 10 working days — confirmed, not reproducible, or out of scope with a reason |
| Fix and disclosure | Coordinated with you. We will not publish before a fix is available unless the issue is already public |
| Credit | Named in the advisory, unless you prefer otherwise |

This is a small project. Those are honest targets rather than a contractual SLA.

### Please do not

- Test against other people's devices or accounts.
- Attack the third-party music services plugins interoperate with. Their
  security is theirs; a finding there belongs in their disclosure programme, not
  this one.
- Open a public issue, a public PR, or a social media thread before the
  coordinated disclosure.

---

## Threat model

The core assumption, stated plainly:

> **A plugin is semi-trusted code running on the user's device, talking to the
> network on the user's behalf.**

Semi-trusted means neither of the two comfortable extremes. It is not hostile
code we are trying to contain in a real sandbox — Dart in-process offers no such
boundary, and pretending otherwise would be the most dangerous claim in this
document. Nor is it host code we can assume is correct: it is written by
someone else, it fails in ways the host cannot predict, and it reaches the
network with the user's IP address and, sometimes, the user's credentials.

The design follows from that. Plugins are constrained by **what they are handed**
rather than by what they are prevented from doing:

| Principle | Mechanism |
|---|---|
| Least authority by default | A plugin gets only the facilities its manifest declares; access to anything else throws `SwayvePermissionDeniedException` synchronously. |
| Narrow surfaces | `SwayveHttpClient` offers `get` and `post`. No sockets, no `dart:io`, no filesystem, no arbitrary platform channels. |
| No ambient authority | `SwayvePluginStorage` takes no plugin id and has no key enumeration, so cross-plugin access is not expressible rather than merely forbidden. |
| No hidden execution | Plugins run when the host calls them. No background execution, no scheduler, no wake-ups. |
| Reviewability | Source is required; obfuscated or minified plugins are rejected. Integrity and identity are verified, not confidentiality — see [docs/packaging.md](docs/packaging.md#why-not-encryption). |
| Blast radius | Every host→plugin call is timeout-bounded and error-isolated. A failing plugin goes to `degraded`; the app keeps working. |

### Assets worth protecting

| Asset | Exposure |
|---|---|
| The user's music library and local files | **Not reachable.** No filesystem API exists on the plugin surface. |
| Swayve account credentials | **Not reachable.** A plugin authenticates to its own service only. |
| A plugin's own credentials | Held in the host credential store; reachable only by the owning plugin, only with `external_auth`. |
| Another plugin's storage or credentials | **Not reachable.** Isolation is structural — see above. |
| The user's network identity | **Exposed by design.** Requests leave the user's own device. This is stated, not hidden; see below. |
| Device secrets, identifiers, location, contacts | **Not reachable.** No permission grants any of them. |
| App integrity and availability | Protected by timeouts, error isolation, and the `degraded` state. |

### The exposure we chose deliberately

Swayve runs **no per-plugin proxy**. A plugin's HTTP requests leave the user's
own device, under the user's own IP address and credentials.

That is a real privacy property with two sides, and both are worth stating:

- **In the user's favour:** no Swayve server sits in the path, so no Swayve
  server logs what the user listens to, and there is no Swayve infrastructure to
  breach.
- **Against the user:** the third-party service sees the user's IP address and
  whatever the plugin sends it. A plugin's upstream learns things about the user
  that Swayve does not.

A user installing a plugin should understand this. It is why `network.hosts` is
a declared, readable allow-list rather than an implementation detail.

---

## What the model does and does not protect

Being precise here matters more than sounding reassuring.

### Protected

- **Escalation to facilities not declared.** Enforced by the host at context
  construction, using the same `SwayvePermissionEnforcement` mixin the test
  harness uses, so a
  permission mistake fails at `dart test`.
- **Cross-plugin access.** No API expresses it.
- **Requests to undeclared hosts.** Refused by the host's HTTP client before
  they leave the device.
- **Tampered or corrupted bundles.** SHA-256 per file plus a canonical bundle
  digest; a mismatch stops the load, with no "load anyway" option.
- **Archive extraction attacks.** Traversal, symlinks, absolute paths, drive
  letters, zip bombs, and oversized or over-numerous entries are all rejected,
  with every resolved path checked against the destination root **after**
  normalisation. See [docs/packaging.md](docs/packaging.md#extraction-safety).
- **Arbitrary code on iOS.** `runtime: bundled` with platform `ios` is a hard
  validator error with no override. See [docs/platforms.md](docs/platforms.md).
- **Availability of the app.** A hanging, throwing or crashing plugin degrades
  itself, not Swayve.

### Not protected

State these to yourself before trusting a plugin:

- **Memory isolation.** A `compiled` plugin runs in the app's Dart isolate. It
  is not sandboxed at the process level and there is no OS boundary between it
  and host memory. The permission model constrains what a *well-behaved* plugin
  is handed; it is not a containment boundary against a determined attacker with
  code in the process.
- **What a plugin does with data it legitimately receives.** If a user grants a
  plugin their credentials for a service, the plugin has them. Nothing
  technically prevents it misusing them; review and reputation do.
- **The plugin's upstream service.** Swayve cannot vouch for the security,
  privacy or behaviour of a third-party API.
- **Confidentiality of plugin code.** Not a goal. Code that runs on the user's
  device cannot be secret from the user.
- **Trust in a signature.** Signing works; **key distribution does not exist
  yet**. A valid signature today proves the bundle is internally consistent and
  was signed by *some* key, which is only useful if you already know which key
  to expect. There is no trust store and no revocation list. See
  [docs/publishing.md](docs/publishing.md#what-does-not-exist-yet).
- **At-rest protection of stored credentials.** The credential store's interface
  is specified; the host-side secure backing is **not implemented in v1**,
  because the client has no plugin system at all yet. See
  [docs/permissions.md](docs/permissions.md#what-is-not-built-yet).
- **A malicious plugin author.** The model reduces what a plugin can reach and
  makes what it reaches for declared and readable. It does not make installing
  an untrusted plugin safe.

---

## In scope for a report

- Permission enforcement that can be bypassed.
- Cross-plugin access to storage or credentials.
- Archive handling: path traversal, symlink escape, zip bombs, resource
  exhaustion, or any way to write outside the destination root.
- Integrity or signature verification that accepts something it should reject.
- Validator rules that can be evaded — particularly the `bundled` + `ios` rule.
- Anything that lets a plugin escape its declared `network.hosts`.
- Credential or token leakage, including into logs.
- A crash, hang or resource exhaustion in the host caused by a plugin, since
  failure isolation is a security property here.

## Out of scope

- Vulnerabilities in a third-party music service.
- The absence of features listed above as not implemented — those are known
  gaps, documented as such, and reporting them as findings does not help.
- Anything requiring physical access to an unlocked device, or an already
  compromised OS.
- The fact that plugin source is readable. That is intended.
- Social engineering of maintainers or users.
- Automated scanner output with no demonstrated impact.

---

## Supported versions

This project is pre-1.0. Its version numbers do not yet carry a stability
promise, and neither does this policy pretend otherwise.

| Version | Supported |
|---|---|
| Latest release on `main` | ✅ Security fixes |
| Any earlier release | ❌ Upgrade to the latest |

There are no long-term support branches and no backports. A security fix ships
in a new release; the remedy is to update. When the project reaches 1.0 this
table will be replaced with a real support window.

The same applies to plugins in this repository: fixes land in a new plugin
version, published as a new tag and release. See
[docs/publishing.md](docs/publishing.md).
