import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The bundle file extension, without the dot.
const String kBundleExtension = 'swayveplugin';

/// The manifest member of a bundle.
const String kBundleManifest = 'plugin.json';

/// The integrity member of a bundle.
const String kBundleIntegrity = 'integrity.json';

/// The signature member of a bundle.
const String kBundleSignature = 'signature.json';

/// Members that the bundle digest deliberately does not cover.
///
/// `integrity.json` cannot hash itself, and `signature.json` is written after
/// the digest exists.
const Set<String> kDigestExcludedMembers = <String>{
  kBundleIntegrity,
  kBundleSignature,
};

/// The digest algorithm this build implements.
const String kDigestAlgorithm = 'sha256';

/// Largest single member, uncompressed.
const int kMaxEntrySizeBytes = 64 * 1024 * 1024;

/// Largest whole bundle, uncompressed.
const int kMaxTotalSizeBytes = 256 * 1024 * 1024;

/// Largest number of members.
const int kMaxEntryCount = 10000;

/// The lowercase hex sha256 of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Orders archive member paths byte-wise ascending over their UTF-8 encoding.
///
/// `String.compareTo` orders by UTF-16 code unit, which differs from byte order
/// above the BMP. The bundle digest is a cross-implementation contract, so it
/// says bytes and means bytes.
int compareBundlePaths(String a, String b) {
  final List<int> left = utf8.encode(a);
  final List<int> right = utf8.encode(b);
  final int shared = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < shared; i++) {
    if (left[i] != right[i]) {
      return left[i] - right[i];
    }
  }
  return left.length - right.length;
}

/// The canonical string the bundle digest is taken over.
///
/// `"<path>\n<sha256>\n"` per file, paths sorted byte-wise ascending,
/// excluding [kDigestExcludedMembers].
String canonicalDigestInput(Map<String, String> fileHashes) {
  final List<String> paths = fileHashes.keys
      .where((String path) => !kDigestExcludedMembers.contains(path))
      .toList()
    ..sort(compareBundlePaths);
  final StringBuffer buffer = StringBuffer();
  for (final String path in paths) {
    buffer
      ..write(path)
      ..write('\n')
      ..write(fileHashes[path])
      ..write('\n');
  }
  return buffer.toString();
}

/// The bundle digest for [fileHashes].
String bundleDigest(Map<String, String> fileHashes) =>
    sha256Hex(utf8.encode(canonicalDigestInput(fileHashes)));

/// Builds the `integrity.json` object for [fileHashes].
Map<String, Object?> buildIntegrityDocument({
  required Map<String, String> fileHashes,
  required String generator,
}) {
  final List<String> paths = fileHashes.keys
      .where((String path) => !kDigestExcludedMembers.contains(path))
      .toList()
    ..sort(compareBundlePaths);
  return <String, Object?>{
    'algorithm': kDigestAlgorithm,
    'files': <String, Object?>{
      for (final String path in paths) path: fileHashes[path],
    },
    'digest': bundleDigest(fileHashes),
    'generator': generator,
  };
}

/// The unsigned `signature.json` body.
Map<String, Object?> unsignedSignatureDocument() =>
    <String, Object?>{'signed': false, 'algorithm': 'none'};

/// Encodes [document] the one way this tool ever encodes JSON into a bundle:
/// two-space indent, LF endings, one trailing newline.
///
/// Determinism starts here. Anything that varies between runs, including map
/// iteration order, has to be settled before this is called.
Uint8List encodeBundleJson(Map<String, Object?> document) {
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  return Uint8List.fromList(utf8.encode('${encoder.convert(document)}\n'));
}

/// The bundle filename for [entrypoint] at [version].
String bundleFileName(String entrypoint, String version) =>
    '$entrypoint-$version.$kBundleExtension';

/// The sidecar checksum filename for [entrypoint] at [version].
String checksumFileName(String entrypoint, String version) =>
    '$entrypoint-$version.sha256';
