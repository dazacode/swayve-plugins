/// How badly a diagnostic wants your attention.
enum Severity {
  /// The manifest or bundle is not usable. Never packaged, never loaded.
  error,

  /// Legal but suspicious. `--strict` promotes these to errors.
  warning,

  /// Worth knowing, never a failure.
  info;

  /// The fixed-width label used in human output, e.g. `ERROR  `.
  String get label => name.toUpperCase();
}

/// Stable machine codes.
///
/// These are public API: CI jobs, dashboards and the Swayve client are allowed
/// to match on them, so a code is never renamed or reused for a different
/// meaning. New checks get new codes.
abstract final class DiagnosticCodes {
  // --- reading the manifest -------------------------------------------------
  /// No `plugin.json` in the plugin directory.
  static const String manifestNotFound = 'manifest_not_found';

  /// `plugin.json` exists but could not be read off disk.
  static const String manifestUnreadable = 'manifest_unreadable';

  /// `plugin.json` is not well-formed JSON.
  static const String manifestMalformedJson = 'manifest_malformed_json';

  /// The manifest's top level is not a JSON object.
  static const String manifestNotObject = 'manifest_not_object';

  // --- structural (mirrors the JSON Schema) ---------------------------------
  /// A required property is absent.
  static const String fieldRequired = 'field_required';

  /// A property that `additionalProperties: false` forbids.
  static const String fieldUnknown = 'field_unknown';

  /// The JSON type is wrong.
  static const String fieldType = 'field_type';

  /// A string violated its `pattern`.
  static const String fieldPattern = 'field_pattern';

  /// A value is outside the closed vocabulary.
  static const String fieldEnum = 'field_enum';

  /// A string or array is too short or too long.
  static const String fieldLength = 'field_length';

  /// A number is outside `minimum`/`maximum`.
  static const String fieldRange = 'field_range';

  /// An array declared `uniqueItems` has a repeat.
  static const String fieldDuplicate = 'field_duplicate';

  /// A `const`-valued field carries something else.
  static const String fieldConst = 'field_const';

  /// A human-readable string carries emoji where the contract forbids them.
  static const String fieldEmoji = 'field_emoji';

  // --- compatibility --------------------------------------------------------
  /// `schemaVersion` is not the version this build understands.
  static const String unsupportedSchemaVersion = 'unsupported_schema_version';

  /// `swayvePluginApi` is higher than this build's API level.
  static const String unsupportedPluginApi = 'unsupported_plugin_api';

  // --- cross-field rules, CONTRACT section 2 --------------------------------
  /// Rule 1a. A declared capability cannot work without a permission that is
  /// missing.
  static const String capabilityRequiresPermission =
      'capability_requires_permission';

  /// Rule 1b. A capability that usually reaches an external service, declared
  /// without the `network` permission.
  static const String capabilityExpectsNetwork = 'capability_expects_network';

  /// Rule 2. A permission is declared that no declared capability implies.
  static const String permissionNotImplied = 'permission_not_implied';

  /// Rule 3. `media.downloadable` without the `streaming` capability.
  static const String downloadableRequiresStreaming =
      'downloadable_requires_streaming';

  /// Rule 4. `runtime: bundled` cannot ship to iOS.
  static const String bundledRuntimeNotAllowedOnIos =
      'bundled_runtime_not_allowed_on_ios';

  /// Rule 5. `network` permission with nothing declared in `network.hosts`.
  static const String networkPermissionWithoutHosts =
      'network_permission_without_hosts';

  /// Rule 6. The last segment of `id` does not equal `entrypoint`.
  static const String entrypointIdMismatch = 'entrypoint_id_mismatch';

  /// Rule 7. The plugin's directory name does not equal `entrypoint`.
  static const String directoryNameMismatch = 'directory_name_mismatch';

  /// Rule 8. A first-party plugin id with a non-Swayve author.
  static const String firstPartyAuthorMismatch = 'first_party_author_mismatch';

  /// Rule 9. A `0.x` version: the plugin API surface is still unstable.
  static const String prereleaseApiUnstable = 'prerelease_api_unstable';

  /// Rule 10. A path-valued field that is absolute, escaping or malformed.
  static const String unsafeRelativePath = 'unsafe_relative_path';

  // --- setting descriptors, CONTRACT section 5 ------------------------------
  /// Two settings share an `id`.
  static const String settingDuplicateId = 'setting_duplicate_id';

  /// `type: select` without `options`.
  static const String settingOptionsRequired = 'setting_options_required';

  /// `options` on a setting that is not a `select`.
  static const String settingOptionsNotAllowed = 'setting_options_not_allowed';

  /// Two options share a `value`.
  static const String settingDuplicateOption = 'setting_duplicate_option';

  /// `default` does not match the declared `type`.
  static const String settingDefaultTypeMismatch =
      'setting_default_type_mismatch';

  /// `default` of a `select` is not one of its `options`.
  static const String settingDefaultNotAnOption =
      'setting_default_not_an_option';

  /// `min`/`max` on a setting that is not an `int`.
  static const String settingRangeNotAllowed = 'setting_range_not_allowed';

  /// `min` is greater than `max`.
  static const String settingRangeInverted = 'setting_range_inverted';

  /// `default` falls outside `min`..`max`.
  static const String settingDefaultOutOfRange = 'setting_default_out_of_range';

  /// A `secret` setting without the `external_auth` permission.
  static const String secretSettingRequiresExternalAuth =
      'secret_setting_requires_external_auth';

  // --- packaging ------------------------------------------------------------
  /// A file the bundle format requires is missing from the plugin directory.
  static const String missingRequiredFile = 'missing_required_file';

  /// `licenses/` exists but has no files in it.
  static const String licensesEmpty = 'licenses_empty';

  /// `icon` names a file that is not in the plugin directory.
  static const String iconFileMissing = 'icon_file_missing';

  /// This build cannot sign, so `--key` cannot be honoured.
  static const String signingUnavailable = 'signing_unavailable';

  /// The signing key could not be read or is not 32 bytes.
  static const String signingKeyInvalid = 'signing_key_invalid';

  // --- bundle verification --------------------------------------------------
  /// The file is not a readable ZIP archive.
  static const String archiveUnreadable = 'archive_unreadable';

  /// The archive has no entries.
  static const String archiveEmpty = 'archive_empty';

  /// More than 10,000 entries.
  static const String archiveTooManyEntries = 'archive_too_many_entries';

  /// The declared uncompressed total exceeds the 256 MiB cap.
  static const String archiveTooLarge = 'archive_too_large';

  /// A single entry exceeds the 64 MiB cap.
  static const String entryTooLarge = 'entry_too_large';

  /// An entry path is absolute.
  static const String entryAbsolutePath = 'entry_absolute_path';

  /// An entry path contains a `..` segment.
  static const String entryParentTraversal = 'entry_parent_traversal';

  /// An entry path contains a backslash.
  static const String entryBackslash = 'entry_backslash';

  /// An entry path carries a Windows drive letter or UNC prefix.
  static const String entryDriveLetter = 'entry_drive_letter';

  /// An entry path contains a NUL byte or another control character.
  static const String entryControlCharacter = 'entry_control_character';

  /// An entry is a symbolic link.
  static const String entrySymlink = 'entry_symlink';

  /// Normalising the entry against the destination root escapes the root.
  static const String entryEscapesRoot = 'entry_escapes_root';

  /// Two entries normalise to the same destination path.
  static const String entryDuplicate = 'entry_duplicate';

  /// A file the bundle format requires is missing from the archive.
  static const String bundleMissingMember = 'bundle_missing_member';

  /// The archive filename does not match `<entrypoint>-<version>.swayveplugin`.
  static const String bundleNameMismatch = 'bundle_name_mismatch';

  // --- integrity and signature ----------------------------------------------
  /// `integrity.json` is missing, malformed or the wrong shape.
  static const String integrityMalformed = 'integrity_malformed';

  /// `integrity.json` names a digest algorithm this build does not implement.
  static const String integrityAlgorithmUnsupported =
      'integrity_algorithm_unsupported';

  /// A file listed in `integrity.json` is not in the archive.
  static const String integrityFileMissing = 'integrity_file_missing';

  /// A file in the archive is not listed in `integrity.json`.
  static const String integrityFileUnlisted = 'integrity_file_unlisted';

  /// A file's sha256 does not match the one recorded for it.
  static const String integrityHashMismatch = 'integrity_hash_mismatch';

  /// The recomputed bundle digest does not match the recorded one.
  static const String integrityDigestMismatch = 'integrity_digest_mismatch';

  /// `signature.json` is missing, malformed or the wrong shape.
  static const String signatureMalformed = 'signature_malformed';

  /// The bundle carries no signature.
  static const String signatureAbsent = 'signature_absent';

  /// The signature covers a digest other than the bundle's.
  static const String signatureDigestMismatch = 'signature_digest_mismatch';

  /// The signature does not verify against the public key.
  static const String signatureInvalid = 'signature_invalid';

  /// The bundle's public key is not the one `--pubkey` asked for.
  static const String signatureKeyMismatch = 'signature_key_mismatch';

  // --- usage ----------------------------------------------------------------
  /// The command line was wrong. Always exit code 2.
  static const String badUsage = 'bad_usage';

  /// The tool hit something it did not expect. Always exit code 3.
  static const String internalError = 'internal_error';
}

/// One problem, note or observation about one thing.
///
/// A diagnostic always carries a stable [code] so machines can match on it, and
/// a [pointer] so a human can find the field. [line] is filled in whenever the
/// diagnostic came from a file whose text we still have.
final class Diagnostic {
  /// Creates a diagnostic.
  const Diagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.pointer = '',
    this.source,
    this.line,
  });

  /// Creates an [Severity.error].
  const Diagnostic.error(
    this.code,
    this.message, {
    this.pointer = '',
    this.source,
    this.line,
  }) : severity = Severity.error;

  /// Creates a [Severity.warning].
  const Diagnostic.warning(
    this.code,
    this.message, {
    this.pointer = '',
    this.source,
    this.line,
  }) : severity = Severity.warning;

  /// Creates an [Severity.info].
  const Diagnostic.info(
    this.code,
    this.message, {
    this.pointer = '',
    this.source,
    this.line,
  }) : severity = Severity.info;

  /// Stable machine code, one of [DiagnosticCodes].
  final String code;

  /// How badly this wants attention.
  final Severity severity;

  /// One line, written for the plugin author, not for the tool's maintainer.
  final String message;

  /// RFC 6901 JSON pointer to the offending value. Empty means the document.
  final String pointer;

  /// The file this came from, relative to whatever the tool was pointed at.
  final String? source;

  /// One-based line number of [pointer] in [source], when it is known.
  final int? line;

  /// Returns a copy with [source] and [line] filled in where they were absent.
  Diagnostic withLocation({String? source, int? line}) => Diagnostic(
        code: code,
        severity: severity,
        message: message,
        pointer: pointer,
        source: source ?? this.source,
        line: line ?? this.line,
      );

  /// The `--json` shape. Field names here are public API.
  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'severity': severity.name,
        'message': message,
        'pointer': pointer,
        if (source != null) 'source': source,
        if (line != null) 'line': line,
      };

  @override
  String toString() => '${severity.label} $code $message';
}

/// Everything the tool learned about one target.
final class Report {
  /// Creates a report for [target].
  Report(this.target, [List<Diagnostic>? diagnostics])
      : diagnostics = List<Diagnostic>.unmodifiable(
          diagnostics ?? const <Diagnostic>[],
        );

  /// What was inspected: a plugin directory or a bundle path.
  final String target;

  /// Every diagnostic, in the order the checks produced them.
  final List<Diagnostic> diagnostics;

  /// Extra machine-readable facts a command wants to publish, such as the
  /// artifacts a packaging run wrote.
  final Map<String, Object?> details = <String, Object?>{};

  /// How many [Severity.error] diagnostics there are.
  int get errorCount => _count(Severity.error);

  /// How many [Severity.warning] diagnostics there are.
  int get warningCount => _count(Severity.warning);

  /// How many [Severity.info] diagnostics there are.
  int get infoCount => _count(Severity.info);

  /// Errors and warnings. Infos are not problems.
  int get problemCount => errorCount + warningCount;

  /// Whether this target passed, honouring [strict].
  bool passed({required bool strict}) =>
      errorCount == 0 && (!strict || warningCount == 0);

  int _count(Severity s) =>
      diagnostics.where((Diagnostic d) => d.severity == s).length;

  /// The `--json` shape for one target.
  Map<String, Object?> toJson({required bool strict}) => <String, Object?>{
        'target': target,
        'ok': passed(strict: strict),
        'diagnostics': diagnostics
            .map((Diagnostic d) => d.toJson())
            .toList(growable: false),
        'summary': <String, Object?>{
          'errors': errorCount,
          'warnings': warningCount,
          'infos': infoCount,
        },
        ...details,
      };
}

/// Collects diagnostics while a check runs.
final class DiagnosticSink {
  final List<Diagnostic> _items = <Diagnostic>[];

  /// Everything added so far.
  List<Diagnostic> get diagnostics => List<Diagnostic>.unmodifiable(_items);

  /// Whether any [Severity.error] has been added.
  bool get hasErrors =>
      _items.any((Diagnostic d) => d.severity == Severity.error);

  /// Adds [diagnostic].
  void add(Diagnostic diagnostic) => _items.add(diagnostic);

  /// Adds every diagnostic in [diagnostics].
  void addAll(Iterable<Diagnostic> diagnostics) => _items.addAll(diagnostics);

  /// Adds an error.
  void error(String code, String message, {String pointer = ''}) =>
      add(Diagnostic.error(code, message, pointer: pointer));

  /// Adds a warning.
  void warning(String code, String message, {String pointer = ''}) =>
      add(Diagnostic.warning(code, message, pointer: pointer));

  /// Adds an info note.
  void info(String code, String message, {String pointer = ''}) =>
      add(Diagnostic.info(code, message, pointer: pointer));
}
