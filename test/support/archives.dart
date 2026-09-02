import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One entry in a hand-built archive, including the parts a well-behaved
/// packer would never set.
final class ForgedEntry {
  /// Creates an entry.
  const ForgedEntry(
    this.name, {
    this.content = 'x',
    this.declaredSize,
    this.mode = 420,
    this.compress = false,
  });

  /// The raw path written into the ZIP, backslashes and all.
  final String name;

  /// The entry's actual bytes.
  final String content;

  /// The uncompressed size written into the header, if it should lie.
  final int? declaredSize;

  /// The unix mode. `0xa1ff` marks a symbolic link.
  final int mode;

  /// Whether to deflate. Storing keeps the forged archives fast to build.
  final bool compress;
}

/// Builds a ZIP containing exactly [entries], bypassing every guard the
/// packager applies.
///
/// `ArchiveFile`'s constructor rewrites backslashes, so the name is assigned
/// afterwards. Since archive 4.1.0 `ZipEncoder` rewrites them a second time on
/// the way out, so a name that must reach the verifier with backslashes intact
/// is encoded in its forward-slash form and patched back byte-for-byte
/// afterwards by [_restoreBackslashes] — that is the only way left to produce
/// the archive a Windows-targeting attacker would actually send.
Uint8List forgeArchive(List<ForgedEntry> entries) {
  final Archive archive = Archive();
  for (final ForgedEntry entry in entries) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(entry.content));
    final ArchiveFile file = ArchiveFile(
      'placeholder',
      entry.declaredSize ?? bytes.length,
      bytes,
    )
      ..name = entry.name.replaceAll(r'\', '/')
      ..mode = entry.mode
      ..isFile = true
      ..compression =
          entry.compress ? CompressionType.deflate : CompressionType.none;
    archive.addFile(file);
  }
  final Uint8List encoded = Uint8List.fromList(
    ZipEncoder().encode(
      archive,
      level: 0,
      modified: DateTime.utc(1980),
    ),
  );
  return _restoreBackslashes(encoded, entries);
}

/// Puts back the backslashes `ZipEncoder` rewrote to `/`.
///
/// A ZIP stores each entry's name as raw bytes, once in the local header and
/// once in the central directory, with no checksum over the name. `\` and `/`
/// are both one byte, so overwriting them in place leaves every offset, length
/// and CRC in the file still correct — the result is a well-formed archive that
/// simply names its entries the way a Windows packer would.
Uint8List _restoreBackslashes(Uint8List encoded, List<ForgedEntry> entries) {
  for (final ForgedEntry entry in entries) {
    if (!entry.name.contains(r'\')) {
      continue;
    }
    final List<int> written = utf8.encode(entry.name.replaceAll(r'\', '/'));
    final List<int> wanted = utf8.encode(entry.name);
    for (int i = 0; i + written.length <= encoded.length; i++) {
      bool matches = true;
      for (int j = 0; j < written.length; j++) {
        if (encoded[i + j] != written[j]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        encoded.setRange(i, i + wanted.length, wanted);
      }
    }
  }
  return encoded;
}
