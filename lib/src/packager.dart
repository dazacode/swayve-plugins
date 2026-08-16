import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'bundle.dart';
import 'diagnostics.dart';
import 'manifest.dart';
import 'safe_path.dart';
import 'signing.dart';
import 'tool_version.dart';
import 'validator.dart';

/// Files and directories a plugin directory must have before it can be packaged.
const List<String> kRequiredPluginFiles = <String>[
  'plugin.json',
  'README.md',
  'pubspec.yaml',
];

/// Directories a plugin directory must have before it can be packaged.
const List<String> kRequiredPluginDirectories = <String>[
  'lib',
  'licenses',
  'test',
];

/// The fixed timestamp every bundle entry carries.
///
/// Real modification times are the single largest source of non-determinism in
/// a ZIP, so there are none: every entry is stamped with the earliest instant
/// the ZIP date format can represent.
final DateTime kFixedBundleTimestamp = DateTime.utc(1980, 1, 1);

/// The fixed deflate level. Any level is deterministic given the same encoder;
/// pinning it means a future default change cannot alter existing bundles.
const int kFixedCompressionLevel = 9;

/// The fixed unix mode on every entry: `0644`, no execute bit, no ownership.
const int kFixedEntryMode = 420;

/// One member of a bundle under construction.
final class BundleMember {
  /// Creates a member at [path] holding [bytes].
  BundleMember(this.path, this.bytes);

  /// The member's path inside the bundle, always POSIX-separated.
  final String path;

  /// The member's exact bytes.
  final Uint8List bytes;
}

/// A built bundle, or the reasons it could not be built.
final class BuiltBundle {
  /// Creates a build outcome.
  BuiltBundle({
    required this.report,
    this.bytes,
    this.entrypoint,
    this.version,
    this.digest,
    this.signed = false,
  });

  /// Everything validation and packaging found.
  final Report report;

  /// The bundle bytes, or `null` if it was not built.
  final Uint8List? bytes;

  /// The plugin's entrypoint, which is also the bundle's base name.
  final String? entrypoint;

  /// The plugin's version.
  final String? version;

  /// The bundle digest recorded in `integrity.json`.
  final String? digest;

  /// Whether `signature.json` carries a real signature.
  final bool signed;

  /// The bundle filename, when there is a bundle.
  String? get fileName => entrypoint != null && version != null
      ? bundleFileName(entrypoint!, version!)
      : null;
}

/// Turns a plugin directory into a `.swayveplugin` bundle.
///
/// Order of operations is fixed by the contract: validate first and refuse to
/// package anything that fails, then check the required files exist, then hash,
/// then write. Nothing is emitted for a plugin that did not pass.
final class Packager {
  /// Creates a packager.
  const Packager();

  /// Builds the bundle for [pluginDirectory] entirely in memory.
  ///
  /// Nothing is written; [writeBundle] does that. Keeping the two apart is what
  /// lets the determinism test build the same input twice and compare bytes
  /// without touching the filesystem in between.
  Future<BuiltBundle> build(
    String pluginDirectory, {
    Uint8List? signingSeed,
    bool strict = false,
  }) async {
    final ManifestValidation validation =
        validatePluginDirectory(pluginDirectory);
    final DiagnosticSink sink = DiagnosticSink()
      ..addAll(validation.report.diagnostics);
    final PluginManifest manifest = validation.manifest;

    _checkRequiredFiles(pluginDirectory, manifest, sink);

    final Report report = Report(validation.report.target, sink.diagnostics);
    if (!report.passed(strict: strict)) {
      return BuiltBundle(report: report);
    }

    final String entrypoint = manifest.entrypoint!;
    final String version = manifest.versionString!;

    final List<BundleMember> members = _collectMembers(pluginDirectory);
    final Map<String, String> hashes = <String, String>{
      for (final BundleMember member in members)
        member.path: sha256Hex(member.bytes),
    };
    final Map<String, Object?> integrity = buildIntegrityDocument(
      fileHashes: hashes,
      generator: kGeneratorId,
    );
    final String digest = integrity['digest']! as String;
    members.add(BundleMember(kBundleIntegrity, encodeBundleJson(integrity)));

    final Map<String, Object?> signature;
    if (signingSeed != null) {
      signature = await signBundleDigest(digestHex: digest, seed: signingSeed);
    } else {
      signature = unsignedSignatureDocument();
    }
    members.add(BundleMember(kBundleSignature, encodeBundleJson(signature)));

    return BuiltBundle(
      report: report,
      bytes: encodeDeterministicZip(members),
      entrypoint: entrypoint,
      version: version,
      digest: digest,
      signed: signature['signed'] == true,
    );
  }

  /// Writes [bundle] into [outputDirectory] and returns the paths it wrote.
  ///
  /// Emits `<entrypoint>-<version>.swayveplugin` and a sibling `.sha256` that
  /// holds the archive's own hash in `sha256sum` format.
  List<String> writeBundle(BuiltBundle bundle, String outputDirectory) {
    final Uint8List? bytes = bundle.bytes;
    final String? name = bundle.fileName;
    if (bytes == null || name == null) {
      return const <String>[];
    }
    Directory(outputDirectory).createSync(recursive: true);
    final String bundlePath = p.join(outputDirectory, name);
    File(bundlePath).writeAsBytesSync(bytes, flush: true);

    final String checksumPath = p.join(
      outputDirectory,
      checksumFileName(bundle.entrypoint!, bundle.version!),
    );
    File(checksumPath).writeAsStringSync(
      '${sha256Hex(bytes)}  $name\n',
      flush: true,
    );
    // Reported with forward slashes whatever the platform: these strings end up
    // in CI logs and in `--json`, where a mix of separators is just noise.
    return <String>[
      bundlePath.replaceAll(r'\', '/'),
      checksumPath.replaceAll(r'\', '/'),
    ];
  }

  void _checkRequiredFiles(
    String directory,
    PluginManifest manifest,
    DiagnosticSink sink,
  ) {
    for (final String name in kRequiredPluginFiles) {
      if (!File(p.join(directory, name)).existsSync()) {
        sink.error(
          DiagnosticCodes.missingRequiredFile,
          'a plugin must ship $name, which is missing',
        );
      }
    }
    for (final String name in kRequiredPluginDirectories) {
      final Directory dir = Directory(p.join(directory, name));
      if (!dir.existsSync()) {
        sink.error(
          DiagnosticCodes.missingRequiredFile,
          'a plugin must ship a $name/ directory, which is missing',
        );
        continue;
      }
      if (name == 'licenses' && _filesUnder(dir.path).isEmpty) {
        sink.error(
          DiagnosticCodes.licensesEmpty,
          'licenses/ must not be empty; ship LICENSE and any third-party '
          'notices',
        );
      }
    }
    final String? icon = manifest.icon;
    if (icon != null &&
        pathProblems(icon).isEmpty &&
        !File(p.join(directory, icon)).existsSync()) {
      sink.error(
        DiagnosticCodes.iconFileMissing,
        "icon: '$icon' is declared but there is no such file in the plugin",
        pointer: '/icon',
      );
    }
  }

  List<BundleMember> _collectMembers(String directory) {
    final List<BundleMember> members = <BundleMember>[
      _member(
        kBundleManifest,
        File(p.join(directory, kBundleManifest)).readAsBytesSync(),
      ),
    ];

    void addTree(String sourceSubdirectory, String bundlePrefix) {
      final String root = p.join(directory, sourceSubdirectory);
      if (!Directory(root).existsSync()) {
        return;
      }
      for (final String file in _filesUnder(root)) {
        final String relative =
            p.posix.joinAll(p.split(p.relative(file, from: root)));
        members.add(
          _member(
            '$bundlePrefix$relative',
            File(file).readAsBytesSync(),
          ),
        );
      }
    }

    // The payload carries what the host or the build needs; README travels with
    // it so a bundle is self-describing without cluttering the bundle root,
    // which CONTRACT section 8 pins to exactly five names.
    members.add(
      _member(
        'payload/README.md',
        File(p.join(directory, 'README.md')).readAsBytesSync(),
      ),
    );
    members.add(
      _member(
        'payload/pubspec.yaml',
        File(p.join(directory, 'pubspec.yaml')).readAsBytesSync(),
      ),
    );
    addTree('lib', 'payload/lib/');
    addTree('payload', 'payload/');
    addTree('assets', 'assets/');
    addTree('licenses', 'licenses/');
    return members;
  }

  BundleMember _member(String path, List<int> bytes) =>
      BundleMember(path, normalizeMemberBytes(path, bytes));

  static List<String> _filesUnder(String root) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      return const <String>[];
    }
    final List<String> files = <String>[];
    for (final FileSystemEntity entity
        in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final List<String> parts = p.split(p.relative(entity.path, from: root));
      if (parts.any((String part) => part.startsWith('.'))) {
        continue; // .dart_tool, .DS_Store and friends never travel
      }
      files.add(entity.path);
    }
    files.sort();
    return files;
  }
}

/// Extensions whose bytes get LF-normalised on the way into a bundle.
const Set<String> kTextExtensions = <String>{
  '.dart',
  '.json',
  '.md',
  '.txt',
  '.yaml',
  '.yml',
  '.svg',
  '.html',
  '.css',
  '.js',
  '.xml',
  '.toml',
  '.cfg',
  '.ini',
};

/// Extensionless filenames that are text.
const Set<String> kTextFileNames = <String>{
  'LICENSE',
  'LICENCE',
  'NOTICE',
  'COPYING',
  'AUTHORS',
  'CHANGELOG',
};

/// Whether [path] names a file whose line endings should be normalised.
bool isTextMember(String path) {
  final String extension = p.extension(path).toLowerCase();
  if (kTextExtensions.contains(extension)) {
    return true;
  }
  return kTextFileNames
          .contains(p.basenameWithoutExtension(path).toUpperCase()) &&
      extension.isEmpty;
}

/// Returns [bytes] with CRLF and lone CR collapsed to LF, when [path] is text.
///
/// A checkout on Windows and a checkout on Linux must produce the same bundle,
/// which they cannot if the text they hold differs by a carriage return. Binary
/// members, and any "text" member that turns out to contain a NUL, pass through
/// untouched.
Uint8List normalizeMemberBytes(String path, List<int> bytes) {
  if (!isTextMember(path) || bytes.contains(0)) {
    return Uint8List.fromList(bytes);
  }
  final BytesBuilder out = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    final int b = bytes[i];
    if (b == 0x0d) {
      if (i + 1 < bytes.length && bytes[i + 1] == 0x0a) {
        continue; // the LF right after it is written on the next pass
      }
      out.addByte(0x0a);
      continue;
    }
    out.addByte(b);
  }
  return out.takeBytes();
}

int _byPath(BundleMember a, BundleMember b) =>
    compareBundlePaths(a.path, b.path);

/// Encodes [members] into a byte-for-byte reproducible ZIP.
///
/// Determinism comes from four fixed choices, all of them here: entries sorted
/// by path byte-wise, one fixed timestamp, one fixed compression level, one
/// fixed mode. Nothing about the machine doing the packaging reaches the
/// output.
Uint8List encodeDeterministicZip(List<BundleMember> members) {
  final List<BundleMember> sorted = List<BundleMember>.of(members)
    ..sort(_byPath);
  final Archive archive = Archive();
  for (final BundleMember member in sorted) {
    final ArchiveFile file = ArchiveFile(
      member.path,
      member.bytes.length,
      member.bytes,
    )
      ..mode = kFixedEntryMode
      ..isFile = true
      ..compression = CompressionType.deflate;
    archive.addFile(file);
  }
  final List<int> encoded = ZipEncoder().encode(
    archive,
    level: kFixedCompressionLevel,
    modified: kFixedBundleTimestamp,
  );
  return Uint8List.fromList(encoded);
}
