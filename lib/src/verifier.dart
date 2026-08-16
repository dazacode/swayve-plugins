import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'bundle.dart';
import 'diagnostics.dart';
import 'manifest.dart';
import 'safe_path.dart';
import 'signing.dart';
import 'validator.dart';

/// The notional directory a bundle would be unpacked into.
///
/// Path containment is checked against this rather than against nothing,
/// because "is this path safe" is not a question a path can answer on its own:
/// it depends on where it lands.
const String kDefaultDestinationRoot = '/var/swayve/plugins/pending';

/// One archive entry as the central directory describes it, before anything is
/// decompressed.
final class _RawEntry {
  _RawEntry({
    required this.index,
    required this.name,
    required this.uncompressedSize,
    required this.externalAttributes,
  });

  final int index;
  final String name;
  final int uncompressedSize;
  final int externalAttributes;

  bool get isDirectoryEntry => name.endsWith('/') || name.endsWith('\\');

  /// Whether the unix mode bits mark this entry as a symbolic link.
  ///
  /// Checked straight off the external attributes rather than trusting the
  /// decoder's "was this made on unix" heuristic, because an attacker chooses
  /// the version-made-by byte too.
  bool get isSymlink => (externalAttributes >> 16) & 0xf000 == 0xa000;
}

/// Checks a `.swayveplugin` archive before anyone unpacks it.
///
/// Everything here runs against the central directory first and the contents
/// second, so a hostile archive is rejected without a single byte being written
/// and, for the size caps, without a single byte being inflated.
final class BundleVerifier {
  /// Creates a verifier.
  const BundleVerifier({
    this.destinationRoot = kDefaultDestinationRoot,
    this.expectedPublicKey,
    this.requireSignature = false,
  });

  /// Where the bundle would be unpacked.
  final String destinationRoot;

  /// A public key the bundle's signature must be under, if one was supplied.
  final List<int>? expectedPublicKey;

  /// Whether an unsigned bundle is a failure rather than a note.
  final bool requireSignature;

  /// Verifies [bytes]. [target] is what human output calls the bundle, and
  /// [fileName] is checked against `<entrypoint>-<version>.swayveplugin`.
  Future<Report> verify(
    Uint8List bytes, {
    required String target,
    String? fileName,
  }) async {
    final DiagnosticSink sink = DiagnosticSink();

    final ZipDecoder decoder = ZipDecoder();
    final Archive archive;
    try {
      archive = decoder.decodeBytes(bytes);
    } on Object catch (e) {
      sink.error(
        DiagnosticCodes.archiveUnreadable,
        'not a readable .swayveplugin archive: $e',
      );
      return Report(target, sink.diagnostics);
    }
    if (decoder.directory.filePosition < 0) {
      // No end-of-central-directory record was found: this isn't a zip at
      // all, not merely an empty one. archive 4.x stopped throwing for this
      // case, so it has to be detected explicitly.
      sink.error(
        DiagnosticCodes.archiveUnreadable,
        'not a readable .swayveplugin archive: no end of central directory record found',
      );
      return Report(target, sink.diagnostics);
    }

    final List<_RawEntry> entries = <_RawEntry>[
      for (var i = 0; i < decoder.directory.fileHeaders.length; i++)
        _RawEntry(
          index: i,
          name: decoder.directory.fileHeaders[i].filename,
          uncompressedSize: decoder.directory.fileHeaders[i].uncompressedSize,
          externalAttributes:
              decoder.directory.fileHeaders[i].externalFileAttributes,
        ),
    ];

    _checkExtractionSafety(entries, sink);
    if (sink.hasErrors) {
      // Never touch the contents of an archive that failed the safety gate.
      return Report(target, sink.diagnostics);
    }

    final Map<String, Uint8List> members = _readMembers(archive, entries, sink);
    if (sink.hasErrors) {
      return Report(target, sink.diagnostics);
    }

    final PluginManifest manifest = _checkManifest(members, sink);
    _checkRequiredMembers(members, sink);
    final String? digest = _checkIntegrity(members, sink);
    await _checkSignature(members, digest, sink);
    _checkFileName(fileName, manifest, sink);

    return Report(target, sink.diagnostics);
  }

  // --- CONTRACT section 8 extraction safety ---------------------------------

  void _checkExtractionSafety(List<_RawEntry> entries, DiagnosticSink sink) {
    if (entries.isEmpty) {
      sink.error(DiagnosticCodes.archiveEmpty, 'the archive has no entries');
      return;
    }
    if (entries.length > kMaxEntryCount) {
      sink.error(
        DiagnosticCodes.archiveTooManyEntries,
        'the archive has ${entries.length} entries; the limit is '
        '$kMaxEntryCount',
      );
      return;
    }

    var total = 0;
    final Set<String> seen = <String>{};
    for (final _RawEntry entry in entries) {
      final String where = 'entry ${entry.index} (${_show(entry.name)})';

      if (entry.isSymlink) {
        sink.error(
          DiagnosticCodes.entrySymlink,
          '$where is a symbolic link; bundles carry files only',
        );
      }

      for (final PathProblem problem in pathProblems(entry.name)) {
        if (problem == PathProblem.empty) {
          continue; // an empty name cannot land anywhere; the root check says so
        }
        final String code = switch (problem) {
          PathProblem.empty => DiagnosticCodes.entryEscapesRoot,
          PathProblem.absolute => DiagnosticCodes.entryAbsolutePath,
          PathProblem.parentTraversal => DiagnosticCodes.entryParentTraversal,
          PathProblem.backslash => DiagnosticCodes.entryBackslash,
          PathProblem.driveLetter => DiagnosticCodes.entryDriveLetter,
          PathProblem.controlCharacter => DiagnosticCodes.entryControlCharacter,
        };
        sink.error(code, '$where ${describePathProblem(problem)}');
      }

      if (!staysInsideRoot(destinationRoot, entry.name)) {
        sink.error(
          DiagnosticCodes.entryEscapesRoot,
          '$where does not stay inside the destination directory once '
          'normalised',
        );
      }

      if (entry.uncompressedSize > kMaxEntrySizeBytes) {
        sink.error(
          DiagnosticCodes.entryTooLarge,
          '$where declares ${entry.uncompressedSize} bytes; the per-file '
          'limit is $kMaxEntrySizeBytes',
        );
      }
      total += entry.uncompressedSize;

      final String canonical = canonicalArchivePath(entry.name);
      if (canonical.isNotEmpty && !seen.add(canonical)) {
        sink.error(
          DiagnosticCodes.entryDuplicate,
          '$where unpacks over an earlier entry at the same path',
        );
      }
    }

    if (total > kMaxTotalSizeBytes) {
      sink.error(
        DiagnosticCodes.archiveTooLarge,
        'the archive expands to $total bytes; the limit is '
        '$kMaxTotalSizeBytes',
      );
    }
  }

  Map<String, Uint8List> _readMembers(
    Archive archive,
    List<_RawEntry> entries,
    DiagnosticSink sink,
  ) {
    final Map<String, Uint8List> members = <String, Uint8List>{};
    for (final _RawEntry entry in entries) {
      if (entry.isDirectoryEntry) {
        continue;
      }
      final ArchiveFile? file = entry.index < archive.files.length
          ? archive.files[entry.index]
          : null;
      if (file == null) {
        continue;
      }
      final Object content = file.content;
      final List<int> bytes = content is List<int> ? content : const <int>[];
      if (bytes.length > kMaxEntrySizeBytes) {
        sink.error(
          DiagnosticCodes.entryTooLarge,
          'entry ${_show(entry.name)} inflates to ${bytes.length} bytes; the '
          'per-file limit is $kMaxEntrySizeBytes',
        );
        continue;
      }
      members[canonicalArchivePath(entry.name)] = Uint8List.fromList(bytes);
    }
    return members;
  }

  // --- contents -------------------------------------------------------------

  void _checkRequiredMembers(
    Map<String, Uint8List> members,
    DiagnosticSink sink,
  ) {
    for (final String required in <String>[
      kBundleManifest,
      kBundleIntegrity,
      kBundleSignature,
    ]) {
      if (!members.containsKey(required)) {
        sink.error(
          DiagnosticCodes.bundleMissingMember,
          'the bundle has no $required',
        );
      }
    }
    final bool hasLicense =
        members.keys.any((String path) => path.startsWith('licenses/'));
    if (!hasLicense) {
      sink.error(
        DiagnosticCodes.licensesEmpty,
        'the bundle has no licenses/ entries; a bundle must carry its licence '
        'and any third-party notices',
      );
    }
  }

  PluginManifest _checkManifest(
    Map<String, Uint8List> members,
    DiagnosticSink sink,
  ) {
    final Uint8List? raw = members[kBundleManifest];
    if (raw == null) {
      return const PluginManifest(<String, Object?>{});
    }
    final String text;
    try {
      text = utf8.decode(raw);
    } on FormatException {
      sink.error(
        DiagnosticCodes.manifestMalformedJson,
        '$kBundleManifest in the bundle is not valid UTF-8',
        pointer: '',
      );
      return const PluginManifest(<String, Object?>{});
    }
    final ManifestValidation validation = validateManifestText(
      text,
      target: kBundleManifest,
      source: kBundleManifest,
    );
    sink.addAll(validation.report.diagnostics);
    return validation.manifest;
  }

  String? _checkIntegrity(
    Map<String, Uint8List> members,
    DiagnosticSink sink,
  ) {
    final Uint8List? raw = members[kBundleIntegrity];
    if (raw == null) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw));
    } on FormatException catch (e) {
      sink.error(
        DiagnosticCodes.integrityMalformed,
        '$kBundleIntegrity is not valid JSON: ${e.message}',
      );
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      sink.error(
        DiagnosticCodes.integrityMalformed,
        '$kBundleIntegrity must be a JSON object',
      );
      return null;
    }
    final Object? algorithm = decoded['algorithm'];
    if (algorithm != kDigestAlgorithm) {
      sink.error(
        DiagnosticCodes.integrityAlgorithmUnsupported,
        "$kBundleIntegrity uses algorithm '$algorithm'; this build implements "
        "'$kDigestAlgorithm'",
      );
      return null;
    }
    final Object? files = decoded['files'];
    if (files is! Map<String, Object?>) {
      sink.error(
        DiagnosticCodes.integrityMalformed,
        "$kBundleIntegrity is missing its 'files' object",
      );
      return null;
    }
    final Object? recordedDigest = decoded['digest'];
    if (recordedDigest is! String) {
      sink.error(
        DiagnosticCodes.integrityMalformed,
        "$kBundleIntegrity is missing its 'digest'",
      );
      return null;
    }

    final Map<String, String> actual = <String, String>{
      for (final MapEntry<String, Uint8List> entry in members.entries)
        if (!kDigestExcludedMembers.contains(entry.key))
          entry.key: sha256Hex(entry.value),
    };

    for (final MapEntry<String, Object?> entry in files.entries) {
      final String? actualHash = actual[entry.key];
      if (actualHash == null) {
        sink.error(
          DiagnosticCodes.integrityFileMissing,
          '$kBundleIntegrity lists ${_show(entry.key)}, which is not in the '
          'archive',
        );
        continue;
      }
      if (entry.value != actualHash) {
        sink.error(
          DiagnosticCodes.integrityHashMismatch,
          '${_show(entry.key)} does not match the hash recorded for it',
        );
      }
    }
    for (final String path in actual.keys) {
      if (!files.containsKey(path)) {
        sink.error(
          DiagnosticCodes.integrityFileUnlisted,
          '${_show(path)} is in the archive but not listed in '
          '$kBundleIntegrity',
        );
      }
    }

    final String computed = bundleDigest(actual);
    if (computed != recordedDigest) {
      sink.error(
        DiagnosticCodes.integrityDigestMismatch,
        'the bundle digest is $computed but $kBundleIntegrity records '
        '$recordedDigest',
      );
    }
    return recordedDigest;
  }

  Future<void> _checkSignature(
    Map<String, Uint8List> members,
    String? digest,
    DiagnosticSink sink,
  ) async {
    final Uint8List? raw = members[kBundleSignature];
    if (raw == null) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw));
    } on FormatException catch (e) {
      sink.error(
        DiagnosticCodes.signatureMalformed,
        '$kBundleSignature is not valid JSON: ${e.message}',
      );
      return;
    }
    if (decoded is! Map<String, Object?>) {
      sink.error(
        DiagnosticCodes.signatureMalformed,
        '$kBundleSignature must be a JSON object',
      );
      return;
    }
    if (decoded['signed'] != true) {
      final String message =
          'the bundle is not signed; its contents are intact but nothing '
          'attests to who built it';
      if (requireSignature || expectedPublicKey != null) {
        sink.error(DiagnosticCodes.signatureAbsent, message);
      } else {
        sink.info(DiagnosticCodes.signatureAbsent, message);
      }
      return;
    }
    if (decoded['algorithm'] != kSignatureAlgorithm) {
      sink.error(
        DiagnosticCodes.signatureMalformed,
        "$kBundleSignature uses algorithm '${decoded['algorithm']}'; this "
        "build implements '$kSignatureAlgorithm'",
      );
      return;
    }
    final Object? signedDigest = decoded['digest'];
    if (signedDigest != digest) {
      sink.error(
        DiagnosticCodes.signatureDigestMismatch,
        'the signature covers digest $signedDigest, not the bundle digest '
        '$digest',
      );
      return;
    }
    final List<int>? publicKey = _decodeBase64(decoded['publicKey']);
    final List<int>? signature = _decodeBase64(decoded['signature']);
    if (publicKey == null || signature == null || signedDigest is! String) {
      sink.error(
        DiagnosticCodes.signatureMalformed,
        '$kBundleSignature is missing a usable publicKey or signature',
      );
      return;
    }
    final List<int>? expected = expectedPublicKey;
    if (expected != null && !_sameBytes(expected, publicKey)) {
      sink.error(
        DiagnosticCodes.signatureKeyMismatch,
        'the bundle is signed by key ${keyIdFor(publicKey)}, not the key that '
        'was asked for (${keyIdFor(expected)})',
      );
      return;
    }
    final bool valid = await verifyBundleSignature(
      digestHex: signedDigest,
      publicKey: publicKey,
      signature: signature,
    );
    if (!valid) {
      sink.error(
        DiagnosticCodes.signatureInvalid,
        'the signature does not verify under the public key in '
        '$kBundleSignature',
      );
    }
  }

  void _checkFileName(
    String? fileName,
    PluginManifest manifest,
    DiagnosticSink sink,
  ) {
    final String? entrypoint = manifest.entrypoint;
    final String? version = manifest.versionString;
    if (fileName == null || entrypoint == null || version == null) {
      return;
    }
    final String expected = bundleFileName(entrypoint, version);
    if (fileName != expected) {
      sink.warning(
        DiagnosticCodes.bundleNameMismatch,
        "the file is named '$fileName' but its manifest says it should be "
        "'$expected'",
      );
    }
  }

  static List<int>? _decodeBase64(Object? value) {
    if (value is! String) {
      return null;
    }
    try {
      return base64.decode(base64.normalize(value));
    } on FormatException {
      return null;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Quotes [value] with control characters escaped, so a hostile entry name
  /// cannot smuggle a newline or an escape sequence into the terminal.
  static String _show(String value) {
    final StringBuffer buffer = StringBuffer("'");
    for (final int c in value.codeUnits) {
      if (c < 0x20 || c == 0x7f) {
        buffer.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
      } else {
        buffer.writeCharCode(c);
      }
    }
    return (buffer..write("'")).toString();
  }
}
