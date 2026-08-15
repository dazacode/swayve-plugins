# Contributing

Thanks for wanting to build something here. This document is what review will
actually check.

**Compiling is not sufficient for acceptance.** A plugin that builds, passes
`dart analyze` and returns correct data on the happy path can still be rejected.
Review asks three further questions, in order:

1. Does it respect the architecture — no host special-casing, no attempt at a UI
   surface, no side channel around the permission model?
2. Does it handle failure — timeouts, cancellation, malformed responses, rate
   limits, being signed out?
3. Does it honour its declared permissions — nothing reached for that the
   manifest does not declare, and nothing declared that is not needed?

A plugin that fails any of these is not "nearly there"; it is a plugin that will
degrade the app for someone who installs it.

---

## Before you start

Open an issue first if you are proposing a new plugin. Use the **plugin
proposal** template. It costs you ten minutes and can save you a weekend spent
on something that cannot be accepted — a service whose terms forbid third-party
clients, a design that needs a permission that does not exist, or a plugin that
duplicates one already in review.

For fixes to existing plugins, the tooling or the docs, just open a PR.

---

## Plugin naming and ID namespaces

The manifest `id` is reverse-DNS, at least three segments, matching
`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$`, and at most 128 characters.

| Namespace | Who | Requirement |
|---|---|---|
| `app.swayve.plugins.*` | **First-party only.** Reserved. | `author.name` must be exactly `"Swayve"`. The validator enforces this as an error (`first_party_author_mismatch`). |
| `dev.<username>.swayve.*` | Community | Use your own GitHub username. `dev.alice.swayve.bandcamp`, not `com.bandcamp.plugin`. |

Do not use a namespace belonging to a domain you do not control, and do not use
a service's own reverse-DNS. `com.spotify.…` implies Spotify published it; that
is a claim you cannot make, and it is the kind of thing that gets an entire
plugin ecosystem into trouble rather than just one plugin.

Other naming rules:

- `entrypoint` must equal the plugin's directory name under `plugins/`
  (validator error, and the most common first failure).
- `id`'s last segment should equal `entrypoint` (validator warning). Make them
  match unless you have a reason.
- `name` is what a user reads: 1–64 characters, no emoji, no version number, no
  "for Swayve" suffix. It is already in Swayve.
- The plugin directory, `entrypoint` and package name are `lower_snake_case`.

---

## Manifest requirements

Run the validator before you push. CI runs it with `--strict`, which turns
warnings into errors:

```bash
dart run tools/validate_plugin.dart plugins/my_plugin --strict
```

Review looks past "it validates" at whether the manifest is *honest*:

- **`capabilities`** — declare what you implement and register. A declared
  capability with no registered provider is a defect; assert the two agree with
  `FakeSwayvePluginContext.registeredCapabilities`. Note that `webview` is a
  capability as well as a permission — `plugins/youtube_music` declares it
  because its playback is a host-rendered web view, and omitting it would leave
  the `webview` permission unjustified.
- **`permissions`** — declare the minimum, and be willing to declare **none**.
  An offline plugin passes `--strict` clean with `"permissions": []`; the
  validator only *notes* a data capability without `network`, because whether
  you open a connection is not decidable from a manifest. Over-declaring is what
  warns. If you need `local_plugin_storage` or `clipboard`, say why in your
  plugin's README — neither warns, and neither should be there without a reason.
- **`network.hosts`** — the complete, exact list. Not `*` (which is not a legal
  pattern), not a wildcard broader than you need. `*.googlevideo.com` is fine;
  `*.com` is not.
- **`platforms`** — only what you have actually run. "Should work on Linux" is
  not a claim; it is a bug report waiting to be filed by the one person who
  tries it.
- **`minimumSwayveVersion`** — raise it when you start depending on newer host
  behaviour, not because you happened to develop against a newer build.
- **`description`** — what the plugin adds, in one sentence. Not who wrote it,
  not marketing.

See [docs/plugin-manifest.md](docs/plugin-manifest.md) for the field reference
and every validation rule.

---

## Code quality

Non-negotiable, and checked by CI:

```bash
dart format .                  # must produce no changes
dart analyze --fatal-infos     # must report ZERO issues, not "no errors"
```

`dart analyze` reporting zero *issues* means zero infos and zero warnings too —
CI passes `--fatal-infos`, so an info is a failed build.
The root `analysis_options.yaml` sets the baseline; every other package
`include:`s it. On top of `package:lints/recommended.yaml` it enables
`prefer_final_locals`, `avoid_print`, `require_trailing_commas`,
`unawaited_futures`, `always_declare_return_types`, and — for the SDK —
`public_member_api_docs`.

Further expectations that review enforces by reading:

- **No `dynamic` in public API.** If a type is genuinely open, it is
  `Object?`, and the boundary decodes it.
- **No `dart:io` in the SDK or in a plugin's `lib/`.** All I/O is host-mediated
  through `SwayvePluginContext`. A plugin reaching for `dart:io` has left the
  sandbox conceptually even where nothing stops it mechanically.
- **No code generation.** No `freezed`, `json_serializable` or `build_runner`.
  Serialization is hand-written, matching the client and the SDK.
- **Every public SDK member has a doc comment describing the contract**, not the
  implementation. What must the caller guarantee, what may they rely on, what
  does it throw.
- **Wrap upstream failures in the SDK's exception types.** A raw
  `FormatException` or `TypeError` escaping a provider is a bug: the host
  branches on `SwayvePluginException` subtypes to decide what to tell the user.
- **Honour `SwayveCancellationToken`.** Search runs on every keystroke.
- **Never log secrets.** No tokens, authorization headers, cookies, or redirect
  URLs carrying a code. The host redacts what it recognises; that is a safety
  net, not permission.

---

## Testing expectations

```bash
(cd plugins/my_plugin && dart test)
```

Plugin tests run under `dart test` with `package:test`. The Flutter test runner
is not used — the SDK has no Flutter dependency, so a plugin implementing
provider interfaces never needs one. If yours genuinely does, explain why in its
README.

A plugin PR is expected to cover, at minimum:

- happy-path decode for every provider method;
- pagination, including the last page (`cursor == null`);
- the difference between "not found" (`null`/empty) and "could not find out"
  (a throw) — the host renders these differently;
- malformed JSON → `SwayvePluginMalformedResponseException`;
- 401/403 → `SwayvePluginAuthRequiredException` **if your plugin has a sign-in
  flow**. If it declares no `authentication` capability, map them to
  `SwayvePluginUnavailableException` instead — offering the user a sign-in
  button that leads nowhere is worse than a plain failure;
- 429 → `SwayvePluginRateLimitedException`, with `retryAfter` when present;
- a hang, using `FakeSwayveHttpClient.enqueueHang()`;
- cancellation mid-call, using `SwayveCancellationTokenSource`;
- permission over-reach, using `FakeSwayvePluginContext` constructed with
  **exactly** the manifest's permission set;
- `registeredCapabilities` matching the manifest's `capabilities`;
- every outbound URL checked against `plugin.json`'s `network.hosts`, read from
  the manifest at test time rather than from a constant in your code.

The permission test is the one people skip and the one review will look for
first. Granting your fake more than your manifest declares produces a test suite
that passes and a plugin that throws on a user's device.

Await `context.close()` in teardown — it cancels any hung request and closes the
settings stream, so a forgotten deadline fails the test instead of hanging the
runner.

Tests must not make real network calls. Use `FakeSwayveHttpClient`. A test that
hits a live service is flaky by construction and will be asked to change. If
your fixtures are modelled on an upstream's shape rather than captured from it,
say so in your README the way `plugins/youtube_music` does — a green suite over
invented fixtures proves your parsers, not your request composition.

See [docs/testing.md](docs/testing.md).

---

## Licensing

- Contributions are accepted under **Apache-2.0**, the licence of this
  repository. Opening a PR means you agree your contribution is licensed that
  way.
- Every plugin has a non-empty `licenses/` directory containing its licence and
  notices for anything it bundles. A plugin with an empty `licenses/` does not
  package.
- The manifest's `license` field is an SPDX identifier and must match what is in
  `licenses/`.
- **Do not vendor code you do not have the right to relicense.** If you adapted
  an algorithm, a parser or a protocol implementation from elsewhere, say so in
  the PR and include the original notice.
- Do not commit API keys, client secrets, tokens, or credentials of any kind —
  yours or a service's. A `type: "secret"` setting exists so the user supplies
  their own; see [docs/permissions.md](docs/permissions.md#credentials).

---

## Security restrictions

These are rejection criteria, not guidelines.

| Not accepted | Why |
|---|---|
| Downloading and executing code at runtime | The entire point of the `compiled`/`bundled` split. See [docs/platforms.md](docs/platforms.md). |
| `eval`-like behaviour, or interpreting a remote payload as instructions | Same. A plugin's behaviour must be reviewable from its source. |
| Reaching a host outside `network.hosts` | The declared list is the allow-list a user can read. Working around it defeats the mechanism. |
| **A dependency that brings its own transport** | This is the one that catches people, because the package looks helpful. `dio`, `package:http`, a socket, a cookie jar — every request made through them bypasses `context.http`, and therefore bypasses the `network` permission *and* the host allow-list. The user would have approved a list of hostnames that no longer describes what the plugin can reach. That is a hole in the security model, not a trade-off. Check a candidate's transport before you check its API; `plugins/youtube_music` rejected four otherwise-reasonable packages on exactly this ground and wrote ~300 lines instead. |
| Sending user data to a host unrelated to the plugin's stated purpose | Analytics, telemetry, "anonymous usage stats" — none of it. A plugin talks to its own service and nothing else. |
| Attempting to read another plugin's storage or credentials | Isolation is deliberate. Any attempt is a rejection, not a bug report. |
| Logging tokens, headers or credential-bearing URLs | Logs are read by humans and attached to support tickets. |
| Obfuscated or minified source | Unreviewable code is unacceptable code, regardless of what it does. |
| Bypassing or weakening host timeouts | The host's bounds exist because a plugin cannot be trusted to enforce its own. |
| Circumventing a service's authentication or paywall | Not a technical objection. Plugins interoperate with services; they do not break into them. |

If you find a security issue in this repository, **do not open a public issue**.
Follow [SECURITY.md](SECURITY.md).

---

## Pull request process

1. **Fork and branch.** One logical change per PR. A new plugin and a tooling
   fix are two PRs.
2. **Run the full local gate**, which is exactly what CI runs:

   ```bash
   dart format .
   dart analyze --fatal-infos
   dart run tools/validate_plugin.dart --all --strict
   dart test                             # repo root: swayve_plugin_tools
   (cd plugins/my_plugin && dart test)
   ```

3. **Fill in the PR template.** The interesting boxes are the ones about
   permissions and failure handling; "N/A" on those will send the PR back.
4. **Explain the trade-offs you made**, not just what you did. Reviewers can
   read the diff. What they cannot read is why you chose to fail closed here and
   open there.
5. **Expect review to focus on failure paths.** The happy path is the easy part
   and it is where authors spend their attention; the review will spend its
   attention on what happens when the upstream is down, slow, rate-limiting, or
   returning something new.
6. **CI must be green.** `validate` and `test` both. `--strict` means a warning
   fails the build; if you believe a warning is correct to accept, say so
   explicitly in the PR rather than leaving the reviewer to guess.

### For a new plugin, also

- A `README.md` in the plugin directory: what it does, which service, what the
  user needs (an account? an API key?), what it does *not* do, and any accepted
  validator warning with its justification.
- A `CHANGELOG.md` entry.
- A version starting at `0.1.0`. Pre-1.0 is the honest state for a new plugin,
  and the validator will note it.
- Confirmation that you have run it on every platform listed in `platforms`.
- If `runtime: compiled`: a dependency entry and one map entry in
  `packages/swayve_plugin_registry` (see that package's `README.md`). This is
  what actually makes the plugin activatable by a host app — nothing else in
  the PR does. A `compiled` plugin merged without a registry entry validates,
  tests, and packages cleanly, and still runs nowhere; reviewers should treat
  a missing registry entry as incomplete, not optional.

---

## Documentation changes

Docs are part of the product. Same bar: no filler, no section that restates its
own heading, concrete examples over abstract description, and honesty about what
is not built. If you are documenting something unimplemented, label it —
"Not implemented in v1" or "Planned" — rather than describing it in the present
tense.

If you change a capability, a permission or a manifest rule, the docs, the SDK
and the validator move in the **same PR**. A vocabulary that is documented but
not validated is worse than one that does not exist.

---

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
