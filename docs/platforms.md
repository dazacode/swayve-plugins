# Runtimes and platforms

This is the document to read before you design a plugin, because it decides what
your plugin is allowed to *be*.

Two manifest fields interact here:

```json
"runtime": "compiled",
"platforms": ["android", "ios", "windows"]
```

and one combination is rejected outright.

---

## `compiled` vs `bundled`

| | `compiled` | `bundled` |
|---|---|---|
| What it is | Dart code compiled into a Swayve build at app build time | A `.swayveplugin` archive the host loads at runtime |
| Where the source lives | In this repository | Anywhere; published as a GitHub Release asset |
| How it reaches a user | Inside the app they installed | Downloaded after the app is installed |
| Can execute Dart | Yes — it *is* app code, subject to review and the SDK interfaces | **No.** v1 carries declarative data only |
| Android / Windows / macOS / Linux | allowed | allowed |
| iOS | allowed | **rejected — hard error** |
| Update cadence | App release | Independent of the app |

The trade is exactly what it looks like: `compiled` gives you real behaviour at
the cost of shipping with the app; `bundled` gives you independent updates at
the cost of not being able to run code.

Both reference plugins in this repository — `example` and `youtube_music` — are
`runtime: compiled`. Their source lives here and is compiled into Swayve
dev and test builds **through the SDK interfaces only**, never through a
client-side special case for their ids.

## Platform matrix

| Platform | `compiled` | `bundled` | Notes |
|---|---|---|---|
| `android` | ✅ | ✅ (declarative only) | |
| `ios` | ✅ | ❌ **validator error** | See below. Non-negotiable. |
| `windows` | ✅ | ✅ (declarative only) | |
| `macos` | ✅ | ✅ (declarative only) | |
| `linux` | ✅ | ✅ (declarative only) | |

`platforms` must be non-empty and is a claim about where the plugin has actually
been exercised, not a wish list. `youtube_music` lists
`["android", "ios", "windows"]` because those are the platforms it has been run
on; adding `linux` because it "should work" is how a plugin ends up broken for
the one user who tried it.

At load time the host checks that `platforms` contains the running platform, and
that the plugin's `runtime` is supported there. Failing either is a
compatibility rejection with a user-readable reason —
*"YouTube Music is not available on this device."* — not a crash. See
[versioning.md](versioning.md#the-compatibility-check-order).

Note that no host loads `bundled` archives today, on any platform: the Swayve
client has no plugin loader yet at all. `bundled` is a specified format with a
validator, a packager and a verifier behind it, and no runtime consumer. See
[host-integration.md](host-integration.md).

---

## The iOS restriction

**Swayve cannot download and execute arbitrary compiled Dart or native code on
iOS.**

That is the whole rule. It is not a configuration option, not a limitation of
the current implementation, and not something a future version will lift. Apple
does not permit an app to download and run executable code that was not part of
the reviewed binary, and Dart's iOS toolchain compiles ahead of time for exactly
that reason — there is no JIT to feed and no dynamic library to load. Both the
policy and the runtime point the same way.

So:

- **`runtime: bundled` in v1 carries declarative data only.** A manifest,
  assets, settings descriptors, host-interpreted configuration. It carries **no
  executable Dart**. This is true on every platform, not only iOS — a format
  that can execute code somewhere and not elsewhere would be a format nobody
  could reason about.
- **The validator hard-errors on `bundled` + `ios`:**

  ```
    ERROR   platforms: runtime 'bundled' cannot be listed for 'ios'; a runtime-loaded bundle is not permitted on that platform, so the plugin must be 'compiled' or drop 'ios'   (plugin.json:14)
  ```

  Diagnostic code `bundled_runtime_not_allowed_on_ios`. There is no override
  flag, no `--allow-unsafe`, and no environment variable. Packaging refuses;
  loading would refuse too.
- **The route to iOS is `compiled`.** If your plugin needs to run code on
  iPhone, its source belongs in this repository, reviewed, and compiled into the
  app. That is not a workaround — it is the supported path, and it is what
  `youtube_music` does.

### Why the error and not a warning

A warning would be a lie of convenience. A `bundled` plugin declaring `ios`
describes an artefact that cannot exist: either it contains code, in which case
iOS will never run it, or it contains no code, in which case declaring `ios`
promises a user a plugin that will do nothing. Failing at validation time costs
the developer thirty seconds. Failing at install time costs a user their trust
in the app.

### What "declarative data only" means in practice

v1's `bundled` payload is data the *host* interprets. The host's interpreter is
fixed code, shipped in the reviewed app binary; the bundle chooses among
behaviours the host already has. That distinction — choosing among reviewed
behaviours versus supplying new ones — is what keeps it on the right side of the
line, and it is the same distinction that makes a JSON config file acceptable
where a downloaded `.so` is not.

When `bundled` grows real behaviour, it will grow as a **host-interpreted
declarative format** — a richer vocabulary the host already knows how to
execute. It will never become arbitrary code. Anything that would require
shipping new logic to the device is a `compiled` plugin, by definition.

### What this rules out, honestly

Worth saying plainly so nobody designs against it:

- No third-party plugin marketplace with runtime installation on iOS.
- No hot-fixing a plugin's parsing logic on iOS without an app release.
- No "just download the newer version of the plugin" support answer on iOS.
- No plugin that is genuinely independent of the Swayve release cycle on iOS.

Android, Windows, macOS and Linux could technically allow more. v1 does not take
that path, because a plugin that behaves differently by platform is a plugin
nobody can support, and an ecosystem split along an OS boundary is worse than a
smaller one that is the same everywhere.

---

## Choosing a runtime

| If your plugin… | Use |
|---|---|
| Talks to an API, parses responses, resolves playback | `compiled` |
| Implements any provider interface at all | `compiled` |
| Needs to work on iOS | `compiled` |
| Is configuration, assets, or a description of something the host already knows how to do | `bundled` |
| Must update independently of Swayve releases, and does not need to run code | `bundled` |

In practice, every plugin that implements a provider interface is `compiled`,
because provider interfaces are Dart. If you are unsure, you want `compiled`.

---

## How a `compiled` plugin actually gets activated

Choosing `compiled` says your plugin's code has to be linked into a host binary
at build time. It does not by itself say *which* binaries link it in — that is
a separate, deliberately manual step, and it is worth being precise about it so
"my plugin is compiled" and "my plugin runs" are not confused.

**First-party plugins** (this repository) are activated through
`packages/swayve_plugin_registry` — a small pure-Dart package that depends on
every first-party compiled plugin and re-exports one flat map,
`firstPartyCompiledPlugins: Map<String, SwayvePluginFactory>`, keyed by
manifest id. A host app depends on exactly two things from this platform,
**permanently**, no matter how large the first-party catalogue grows:
`swayve_plugin_sdk` (the interfaces) and `swayve_plugin_registry` (what's
compiled in). Adding `youtube_music` to the registry did not, and a future
`jiosaavn` will not, require touching any host app's `pubspec.yaml` or its
plugin-loading code. See `packages/swayve_plugin_registry/README.md` for the
two-line process of adding a first-party plugin to the map.

A host resolves a verified bundle by looking its manifest id up in
`firstPartyCompiledPlugins`. **An id with no entry is not a validation
failure** — the bundle may be perfectly well-formed — it means this specific
build was not compiled against that plugin, and the host must report that
plainly ("this build of Swayve does not include a compiled implementation of
&lt;name&gt;") rather than treat it as a broken bundle.

**Community `compiled` plugins** cannot be added to the first-party registry —
that map is a trust boundary, not a discovery mechanism, and nothing can
safely download and run arbitrary code on iOS regardless. A community plugin
reaches a device by one of two routes, and both are deliberate, not
workarounds:

1. **Get it merged as first-party.** Once accepted through the PR process in
   [CONTRIBUTING.md](../CONTRIBUTING.md#pull-request-process), it is added to
   `swayve_plugin_registry` like any other, and every host app gains it for
   free on its next dependency bump.
2. **A specific app builder wires it in directly.** Nothing stops a host from
   depending on a plugin package on its own and merging it into the registry
   at the call site — `firstPartyCompiledPlugins` is a plain `const Map`,
   so `{...firstPartyCompiledPlugins, myPluginId: myFactory}` composes it with
   local additions without forking the registry package. This is the honest
   escape hatch for a private fork or an enterprise deployment; it is not a
   general distribution channel, because it still requires that specific
   builder to rebuild and ship.

There is deliberately no third option where a plugin registers itself at
runtime without appearing in either place — that would be exactly the
dynamic-code-loading model §7/this document rules out on iOS.

---

## See also

- [packaging.md](packaging.md) — the `.swayveplugin` format and why encryption is not the model
- [plugin-manifest.md](plugin-manifest.md#4-bundled--ios--error) — the validator rule
- [publishing.md](publishing.md) — how a `bundled` archive is distributed
- [host-integration.md](host-integration.md) — what a host must implement to load anything at all
