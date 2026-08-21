import 'diagnostics.dart';
import 'json_source.dart';
import 'manifest.dart';
import 'safe_path.dart';
import 'vocabulary.dart';

/// The checks a JSON Schema cannot express.
///
/// One method per rule, run in the order CONTRACT section 2 lists them, so the
/// output of a failing manifest is stable enough to diff.
final class ManifestRules {
  /// Creates a rule runner for [manifest] writing into [sink].
  ManifestRules(this.manifest, this.sink, {this.directoryName});

  /// The manifest under test.
  final PluginManifest manifest;

  /// Where diagnostics go.
  final DiagnosticSink sink;

  /// The plugin's directory name, when the manifest was read off disk.
  /// Rule 7 is skipped when this is `null`.
  final String? directoryName;

  /// Runs the compatibility gate and every cross-field rule.
  void runAll() {
    checkCompatibility();
    rule1CapabilityRequiresPermission();
    rule1bCapabilityExpectsNetwork();
    rule1cCapabilityRequiresCapability();
    rule2OverPermissioned();
    rule3DownloadableRequiresStreaming();
    rule4BundledRuntimeNotAllowedOnIos();
    rule5NetworkPermissionWithoutHosts();
    rule6EntrypointMatchesIdSuffix();
    rule7DirectoryNameMatchesEntrypoint();
    rule8FirstPartyAuthor();
    rule9VersionStability();
    rule10PathsAreSafe();
    rule11SourceIsReachable();
    rule12SessionCaptureIsWellFormed();
    checkSettings();
  }

  /// `schemaVersion` and `swayvePluginApi` against what this build knows.
  ///
  /// This is the manifest-side half of the host's compatibility check
  /// (CONTRACT section 10). It answers in the same voice the host must use to a
  /// user: the plugin is fine, Swayve is behind.
  ///
  /// Only a *newer* `schemaVersion` is rejected, the same shape as the
  /// `swayvePluginApi` check below. The format only ever widens — a new
  /// capability, a new optional field — so a build that understands version 2
  /// reads a version 1 manifest exactly as a v1 build would. There is
  /// deliberately no "no longer supported" branch: nothing has ever been
  /// removed from the format, so there is nothing yet to age out.
  void checkCompatibility() {
    final int? schemaVersion = manifest.schemaVersion;
    if (schemaVersion != null && schemaVersion > kManifestSchemaVersion) {
      sink.error(
        DiagnosticCodes.unsupportedSchemaVersion,
        'schemaVersion: $schemaVersion is newer than this build '
        'understands (schemaVersion $kManifestSchemaVersion); '
        'this plugin requires a newer version of Swayve',
        pointer: '/schemaVersion',
      );
    }
    final int? api = manifest.swayvePluginApi;
    if (api != null && api > kSwayvePluginApiVersion) {
      sink.error(
        DiagnosticCodes.unsupportedPluginApi,
        'swayvePluginApi: this plugin targets API level $api but this build '
        'implements level $kSwayvePluginApiVersion; it requires a newer '
        'version of Swayve',
        pointer: '/swayvePluginApi',
      );
    }
  }

  /// Rule 1a. A capability that is unusable without one or more permissions.
  ///
  /// Only `webview`, `authentication` and `session_capture` land here, and
  /// only because the capability and the permission(s) describe the same act:
  /// a plugin that declares `webview` without the `webview` permission — or
  /// `session_capture` without both `webview` and `external_auth` — is
  /// describing a plugin that cannot do the thing it says it does. A
  /// capability requiring more than one permission emits one diagnostic per
  /// permission missing, in the order [kCapabilityRequiredPermission] lists
  /// them.
  void rule1CapabilityRequiresPermission() {
    final List<String> capabilities = manifest.capabilities;
    final Set<String> permissions = manifest.permissions.toSet();
    for (var i = 0; i < capabilities.length; i++) {
      final String capability = capabilities[i];
      final List<String>? required = kCapabilityRequiredPermission[capability];
      if (required == null) {
        continue;
      }
      for (final String permission in required) {
        if (permissions.contains(permission)) {
          continue;
        }
        sink.error(
          DiagnosticCodes.capabilityRequiresPermission,
          "capabilities: '$capability' requires permission '$permission'",
          pointer: joinPointer('/capabilities', i),
        );
      }
    }
  }

  /// Rule 1b. A data capability declared without the `network` permission.
  ///
  /// This is advisory, and deliberately so. Whether a plugin actually opens a
  /// connection is not decidable from its manifest: a `search` provider can
  /// perfectly well serve a catalogue that ships inside the plugin, and an
  /// offline plugin that honestly declares no permissions must not fail CI for
  /// its honesty. That is why this is [Severity.info] and not a warning —
  /// `--strict` promotes warnings, and there is nothing here to promote.
  ///
  /// The real enforcement is at runtime and it is exact: `context.http` throws
  /// `SwayvePermissionDeniedException` unless `network` is declared, and
  /// `FakeSwayvePluginContext` reproduces that in the plugin's own tests. An
  /// under-declared plugin is therefore caught by execution, where the answer
  /// is knowable, rather than guessed at here. Over-declaration is the
  /// direction that costs a user trust, and it stays a warning under
  /// [rule2OverPermissioned].
  void rule1bCapabilityExpectsNetwork() {
    if (manifest.permissions.contains('network')) {
      return;
    }
    final List<String> capabilities = manifest.capabilities;
    for (var i = 0; i < capabilities.length; i++) {
      final String capability = capabilities[i];
      if (!kNetworkExpectingCapabilities.contains(capability)) {
        continue;
      }
      sink.info(
        DiagnosticCodes.capabilityExpectsNetwork,
        "capabilities: '$capability' usually reaches an external service; "
        "declare the 'network' permission unless this plugin serves purely "
        'local data',
        pointer: joinPointer('/capabilities', i),
      );
    }
  }

  /// Rule 1c. A capability that is unusable without another capability.
  ///
  /// Only `personal_library` lands here today, and for the same reason rule 1a
  /// exists: `personal_library` describes the signed-in user's own liked
  /// tracks, which has no meaning without a session, and `authentication` is
  /// what a plugin declares to say it can obtain one. This is a distinct rule
  /// from 1a because the missing thing is a capability, not a permission — a
  /// manifest could declare `external_auth` without `authentication` and this
  /// rule would still fire, because holding the permission is not the same as
  /// declaring the flow that uses it.
  void rule1cCapabilityRequiresCapability() {
    final List<String> capabilities = manifest.capabilities;
    final Set<String> declared = capabilities.toSet();
    for (var i = 0; i < capabilities.length; i++) {
      final String capability = capabilities[i];
      final String? required = kCapabilityRequiredCapability[capability];
      if (required == null || declared.contains(required)) {
        continue;
      }
      sink.error(
        DiagnosticCodes.capabilityRequiresCapability,
        "capabilities: '$capability' requires capability '$required'",
        pointer: joinPointer('/capabilities', i),
      );
    }
  }

  /// Rule 2. A permission nothing asked for is a warning, not an error.
  void rule2OverPermissioned() {
    final Set<String> implied = permissionsJustifiedBy(manifest.capabilities);
    // A `secret` setting is the other legitimate reason to hold external_auth.
    final bool hasSecretSetting = manifest.settings
        .any((Map<String, Object?> s) => s['type'] == 'secret');
    if (hasSecretSetting) {
      implied.add('external_auth');
    }
    final List<String> permissions = manifest.permissions;
    for (var i = 0; i < permissions.length; i++) {
      final String permission = permissions[i];
      if (implied.contains(permission) ||
          kSelfJustifyingPermissions.contains(permission) ||
          !kPermissions.contains(permission)) {
        continue;
      }
      sink.warning(
        DiagnosticCodes.permissionNotImplied,
        "permissions: '$permission' is declared but no declared capability "
        'needs it; drop it or add the capability that does',
        pointer: joinPointer('/permissions', i),
      );
    }
  }

  /// Rule 3. Claiming downloads without the `streaming` capability.
  void rule3DownloadableRequiresStreaming() {
    if (!manifest.mediaFlag('downloadable')) {
      return;
    }
    if (manifest.capabilities.contains('streaming')) {
      return;
    }
    sink.error(
      DiagnosticCodes.downloadableRequiresStreaming,
      "media: 'downloadable' is true but the plugin does not declare the "
      "'streaming' capability",
      pointer: '/media/downloadable',
    );
  }

  /// Rule 4. `bundled` cannot ship to iOS, and this does not soften.
  void rule4BundledRuntimeNotAllowedOnIos() {
    if (manifest.runtime != 'bundled') {
      return;
    }
    final int index = manifest.platforms.indexOf('ios');
    if (index < 0) {
      return;
    }
    sink.error(
      DiagnosticCodes.bundledRuntimeNotAllowedOnIos,
      "platforms: runtime 'bundled' cannot be listed for 'ios'; a runtime"
      '-loaded bundle is not permitted on that platform, so the plugin must '
      "be 'compiled' or drop 'ios'",
      pointer: joinPointer('/platforms', index),
    );
  }

  /// Rule 5. Holding `network` while declaring nowhere to go.
  void rule5NetworkPermissionWithoutHosts() {
    final int index = manifest.permissions.indexOf('network');
    if (index < 0) {
      return;
    }
    if (manifest.networkHosts.isNotEmpty) {
      return;
    }
    sink.warning(
      DiagnosticCodes.networkPermissionWithoutHosts,
      'network: permission declared but no network.hosts listed',
      pointer: manifest.hasNetworkObject
          ? '/network/hosts'
          : joinPointer('/permissions', index),
    );
  }

  /// Rule 6. The last segment of `id` should be the `entrypoint`.
  void rule6EntrypointMatchesIdSuffix() {
    final String? id = manifest.id;
    final String? entrypoint = manifest.entrypoint;
    if (id == null || entrypoint == null || !id.contains('.')) {
      return;
    }
    final String lastSegment = id.split('.').last;
    if (lastSegment == entrypoint) {
      return;
    }
    sink.warning(
      DiagnosticCodes.entrypointIdMismatch,
      "entrypoint: '$entrypoint' does not match the last segment of id "
      "('$lastSegment'); they should be the same name",
      pointer: '/entrypoint',
    );
  }

  /// Rule 7. The directory under `plugins/` must be the `entrypoint`.
  void rule7DirectoryNameMatchesEntrypoint() {
    final String? directory = directoryName;
    final String? entrypoint = manifest.entrypoint;
    if (directory == null || entrypoint == null || directory == entrypoint) {
      return;
    }
    sink.error(
      DiagnosticCodes.directoryNameMismatch,
      "entrypoint: the plugin directory is named '$directory' but entrypoint "
      "is '$entrypoint'; they must be identical",
      pointer: '/entrypoint',
    );
  }

  /// Rule 8. The first-party namespace belongs to Swayve.
  void rule8FirstPartyAuthor() {
    final String? id = manifest.id;
    if (id == null || !id.startsWith(kFirstPartyIdPrefix)) {
      return;
    }
    final String? author = manifest.authorName;
    if (author == kFirstPartyAuthorName) {
      return;
    }
    sink.error(
      DiagnosticCodes.firstPartyAuthorMismatch,
      "author: id '$id' is in the first-party namespace "
      "'$kFirstPartyIdPrefix', which requires "
      "author.name to be '$kFirstPartyAuthorName' "
      '(found ${author == null ? 'nothing' : "'$author'"})',
      pointer: '/author/name',
    );
  }

  /// Rule 9. A `0.x` plugin is telling you its surface may still move.
  void rule9VersionStability() {
    final String? raw = manifest.versionString;
    if (raw == null) {
      return;
    }
    final version = manifest.version;
    if (version == null || !version.isUnstable) {
      return;
    }
    sink.info(
      DiagnosticCodes.prereleaseApiUnstable,
      'version $raw is pre-1.0; the plugin API surface is unstable',
      pointer: '/version',
    );
  }

  /// Rule 10. Every path-valued field must be relative and must stay put.
  void rule10PathsAreSafe() {
    for (final (String pointer, String value) in manifest.pathFields) {
      final List<PathProblem> problems = pathProblems(value);
      if (problems.isEmpty) {
        continue;
      }
      final String reasons = problems.map(describePathProblem).join(' and it ');
      sink.error(
        DiagnosticCodes.unsafeRelativePath,
        '${pointer.substring(1)}: path must be relative to the plugin '
        "directory; '$value' $reasons",
        pointer: pointer,
      );
    }
  }

  /// Rule 11. A `source` block that describes somewhere nothing can be sent.
  ///
  /// Both halves are advisory, and for the same reason rule 1b is: what a
  /// plugin can actually be asked for is not decidable from a manifest, and a
  /// plugin that is honestly a little of both must not fail CI for its honesty.
  ///
  /// The first half catches the shape that produces a broken filter row: a
  /// plugin declaring `search` and a `source` naming no content types is
  /// telling the host both "put a query to me" and "there is nothing I answer
  /// for", and the host resolves that by never offering the source at all —
  /// which reads to a user as a plugin that installed and then did nothing.
  ///
  /// The second half catches the opposite: a `source` block on a plugin that
  /// declares neither `search` nor `catalog` is describing a source that no
  /// query and no browse can reach. That is a plugin filling in a field
  /// because it exists rather than because it is one, and the cost is a source
  /// row a person can select and get nothing from.
  void rule11SourceIsReachable() {
    if (!manifest.hasSourceObject) {
      return;
    }
    final Set<String> capabilities = manifest.capabilities.toSet();
    if (capabilities.contains('search') &&
        manifest.sourceContentTypes.isEmpty) {
      sink.info(
        DiagnosticCodes.sourceDeclaresNoContentTypes,
        "source: the 'search' capability is declared but source.contentTypes "
        'names nothing this source can be asked for, so a host has nothing to '
        'offer it under',
        pointer: '/source/contentTypes',
      );
    }
    if (!capabilities.contains('search') && !capabilities.contains('catalog')) {
      sink.info(
        DiagnosticCodes.sourceWithoutReachableCapability,
        "source: declared, but the plugin declares neither 'search' nor "
        "'catalog', so nothing can be asked of it; a plugin that only enriches "
        'what the host already has is not a source',
        pointer: '/source',
      );
    }
  }

  /// Rule 12. A `session_capture` manifest block that does not match its own
  /// capability declaration, or that is malformed where it is present.
  ///
  /// Mirrors rule 11's asymmetric severity: declaring the capability with no
  /// block to back it up is a plugin that cannot do the thing it says it does
  /// (error), while a block with no capability to run it is dead
  /// configuration nothing will ever execute (info) — costly to a user only
  /// in the sense of clutter, not correctness. Once a block is present, its
  /// contents are checked regardless of which way the capability mismatch (if
  /// any) went: a malformed capture entry is still a malformed capture entry.
  void rule12SessionCaptureIsWellFormed() {
    final bool declaresCapability =
        manifest.capabilities.contains('session_capture');
    final bool hasObject = manifest.hasSessionCaptureObject;

    if (declaresCapability && !hasObject) {
      final int index = manifest.capabilities.indexOf('session_capture');
      sink.error(
        DiagnosticCodes.sessionCaptureObjectMissing,
        "capabilities: 'session_capture' is declared but no session_capture "
        'object is present',
        pointer: joinPointer('/capabilities', index),
      );
    }

    if (!hasObject) {
      return;
    }

    if (!declaresCapability) {
      sink.info(
        DiagnosticCodes.sessionCaptureObjectWithoutCapability,
        'session_capture: declared, but the plugin does not declare the '
        "'session_capture' capability, so this block will never run",
        pointer: '/session_capture',
      );
    }

    if (manifest.sessionCaptureHosts.isEmpty) {
      sink.error(
        DiagnosticCodes.sessionCaptureHostsEmpty,
        'session_capture: hosts is empty or missing; the capture flow must '
        'be scoped to at least one host',
        pointer: '/session_capture/hosts',
      );
    }

    final Set<String> declaredSecretIds = manifest.settings
        .where((Map<String, Object?> setting) => setting['type'] == 'secret')
        .map((Map<String, Object?> setting) => setting['id'])
        .whereType<String>()
        .toSet();

    final List<Map<String, Object?>> entries = manifest.sessionCaptureEntries;
    for (var i = 0; i < entries.length; i++) {
      final Map<String, Object?> entry = entries[i];
      final String entryBase = joinPointer('/session_capture/capture', i);

      final Object? from = entry['from'];
      if (from is! String || !kSessionCaptureSources.contains(from)) {
        sink.error(
          DiagnosticCodes.sessionCaptureUnknownSource,
          'session_capture: capture[$i].from '
          "'${from ?? 'missing'}' is not in the closed vocabulary "
          '(${kSessionCaptureSources.join(', ')})',
          pointer: joinPointer(entryBase, 'from'),
        );
      }

      final Object? asSecret = entry['as_secret'];
      if (asSecret is! String || !declaredSecretIds.contains(asSecret)) {
        sink.error(
          DiagnosticCodes.sessionCaptureSecretNotDeclared,
          'session_capture: capture[$i].as_secret '
          "'${asSecret ?? 'missing'}' does not name a 'secret'-typed setting "
          'this manifest declares',
          pointer: joinPointer(entryBase, 'as_secret'),
        );
      }
    }
  }

  /// The setting descriptor rules from CONTRACT section 5.
  void checkSettings() {
    final Set<String> seenIds = <String>{};
    final bool hasExternalAuth = manifest.permissions.contains('external_auth');

    for (final (int index, Map<String, Object?> setting)
        in manifest.indexedSettings) {
      final String base = joinPointer('/settings', index);
      final Object? id = setting['id'];
      final Object? type = setting['type'];
      final Object? options = setting['options'];
      final Object? defaultValue = setting['default'];
      final bool hasDefault = setting.containsKey('default');

      if (id is String && !seenIds.add(id)) {
        sink.error(
          DiagnosticCodes.settingDuplicateId,
          "settings: setting id '$id' is used more than once",
          pointer: joinPointer(base, 'id'),
        );
      }

      if (type == 'select') {
        if (options == null) {
          sink.error(
            DiagnosticCodes.settingOptionsRequired,
            "settings: '${id ?? index}' is a select and must declare options",
            pointer: base,
          );
        }
      } else if (options != null) {
        sink.error(
          DiagnosticCodes.settingOptionsNotAllowed,
          "settings: '${id ?? index}' declares options but its type is "
          "'$type'; only a select takes options",
          pointer: joinPointer(base, 'options'),
        );
      }

      if (options is List<Object?>) {
        final Set<String> seenValues = <String>{};
        for (var i = 0; i < options.length; i++) {
          final Object? option = options[i];
          if (option is Map<String, Object?>) {
            final Object? value = option['value'];
            if (value is String && !seenValues.add(value)) {
              sink.error(
                DiagnosticCodes.settingDuplicateOption,
                "settings: '${id ?? index}' repeats the option value "
                "'$value'",
                pointer: joinPointer(joinPointer(base, 'options'), i),
              );
            }
          }
        }
      }

      if (hasDefault && type is String) {
        final String? expected = _expectedDefaultType(type);
        if (expected != null && !_matchesDefaultType(defaultValue, type)) {
          sink.error(
            DiagnosticCodes.settingDefaultTypeMismatch,
            "settings: '${id ?? index}' has type '$type' so its default must "
            'be a $expected',
            pointer: joinPointer(base, 'default'),
          );
        }
        if (type == 'select' &&
            defaultValue is String &&
            options is List<Object?>) {
          final bool known = options.any(
            (Object? o) =>
                o is Map<String, Object?> && o['value'] == defaultValue,
          );
          if (!known) {
            sink.error(
              DiagnosticCodes.settingDefaultNotAnOption,
              "settings: '${id ?? index}' defaults to '$defaultValue', which "
              'is not one of its options',
              pointer: joinPointer(base, 'default'),
            );
          }
        }
      }

      final Object? min = setting['min'];
      final Object? max = setting['max'];
      if (type != 'int' && (min != null || max != null)) {
        sink.error(
          DiagnosticCodes.settingRangeNotAllowed,
          "settings: '${id ?? index}' declares min/max but its type is "
          "'$type'; only an int takes a range",
          pointer: joinPointer(base, min != null ? 'min' : 'max'),
        );
      }
      if (min is int && max is int && min > max) {
        sink.error(
          DiagnosticCodes.settingRangeInverted,
          "settings: '${id ?? index}' has min $min greater than max $max",
          pointer: joinPointer(base, 'min'),
        );
      }
      if (defaultValue is int && type == 'int') {
        if ((min is int && defaultValue < min) ||
            (max is int && defaultValue > max)) {
          sink.error(
            DiagnosticCodes.settingDefaultOutOfRange,
            "settings: '${id ?? index}' defaults to $defaultValue, outside "
            'its declared range',
            pointer: joinPointer(base, 'default'),
          );
        }
      }

      if (type == 'secret' && !hasExternalAuth) {
        sink.error(
          DiagnosticCodes.secretSettingRequiresExternalAuth,
          "settings: '${id ?? index}' is a secret, which requires the "
          "'external_auth' permission",
          pointer: joinPointer(base, 'type'),
        );
      }
    }
  }

  static String? _expectedDefaultType(String settingType) =>
      switch (settingType) {
        'string' || 'select' || 'secret' => 'string',
        'bool' => 'boolean',
        'int' => 'integer',
        _ => null,
      };

  static bool _matchesDefaultType(Object? value, String settingType) =>
      switch (settingType) {
        'string' || 'select' || 'secret' => value is String,
        'bool' => value is bool,
        'int' => value is int,
        _ => true,
      };
}
