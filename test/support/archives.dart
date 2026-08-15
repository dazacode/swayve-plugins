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
/// afterwards; that is the only way to produce the archive a Windows-targeting
/// attacker would actually send.
Uint8List forgeArchive(List<ForgedEntry> entries) {
  final Archive archive = Archive();
  for (final ForgedEntry entry in entries) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(entry.content));
    final ArchiveFile file = ArchiveFile(
      'placeholder',
      entry.declaredSize ?? bytes.length,
      bytes,
    )
      ..name = entry.name
      ..mode = entry.mode
      ..isFile = true
      ..compress = entry.compress;
    archive.addFile(file);
  }
  return Uint8List.fromList(
    ZipEncoder().encode(
          archive,
          level: 0,
          modified: DateTime.utc(1980),
        ) ??
        const <int>[],
  );
}
