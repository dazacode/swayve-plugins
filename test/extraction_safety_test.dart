import 'dart:typed_data';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

import 'support/archives.dart';

/// Every rule in CONTRACT section 8's extraction-safety list, each proved by an
/// archive built to break exactly that rule.
///
/// These are the checks that stand between a downloaded bundle and someone
/// else's filesystem, so each one gets a hostile archive rather than a
/// hand-waved assertion.
void main() {
  Future<Report> verifyEntries(
    List<ForgedEntry> entries, {
    String destination = '/var/swayve/plugins/pending',
  }) =>
      BundleVerifier(destinationRoot: destination).verify(
        forgeArchive(entries),
        target: 'forged.swayveplugin',
      );

  List<String> codes(Report report) =>
      report.diagnostics.map((Diagnostic d) => d.code).toList(growable: false);

  group('path shape', () {
    test('an absolute path is rejected', () async {
      final Report report =
          await verifyEntries(<ForgedEntry>[const ForgedEntry('/etc/passwd')]);
      expect(codes(report), contains(DiagnosticCodes.entryAbsolutePath));
      expect(report.passed(strict: false), isFalse);
    });

    test('a parent-traversal segment is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry('../../etc/passwd')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryParentTraversal));
    });

    test('traversal hidden mid-path is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry('assets/../../../etc/passwd')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryParentTraversal));
      expect(codes(report), contains(DiagnosticCodes.entryEscapesRoot));
    });

    test('a backslash is rejected, whatever the host platform', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry(r'assets\..\..\evil.txt')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryBackslash));
    });

    test('a drive letter is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry('C:/Windows/System32/evil.dll')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryDriveLetter));
    });

    test('a UNC prefix is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry('//attacker/share/evil.txt')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryDriveLetter));
    });

    test('a NUL byte in the path is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[ForgedEntry('plugin.json${String.fromCharCode(0)}.txt')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryControlCharacter));
    });

    test('a newline in the path is rejected before it reaches a log', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry('ok.txt\nERROR nothing to see here')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryControlCharacter));
      expect(
        report.diagnostics.every((Diagnostic d) => !d.message.contains('\n')),
        isTrue,
        reason: 'a hostile entry name must not break the output format',
      );
    });
  });

  group('containment', () {
    test('containment is decided after normalisation, not before', () async {
      // Every segment looks innocent one at a time; the resolved path is not.
      final Report report = await verifyEntries(
        <ForgedEntry>[const ForgedEntry('a/b/../../../x')],
      );
      expect(codes(report), contains(DiagnosticCodes.entryEscapesRoot));
    });

    test('a path that lands exactly on the root is rejected', () async {
      final Report report =
          await verifyEntries(<ForgedEntry>[const ForgedEntry('a/..')]);
      expect(codes(report), contains(DiagnosticCodes.entryEscapesRoot));
    });

    test('an ordinary nested path stays inside the root', () {
      expect(staysInsideRoot('/dest', 'assets/icon.svg'), isTrue);
      expect(staysInsideRoot('/dest', 'a/b/c/d.txt'), isTrue);
      expect(staysInsideRoot('/dest', '../sibling'), isFalse);
      expect(staysInsideRoot('/dest', '/dest/../other'), isFalse);
      expect(staysInsideRoot(r'C:\dest', 'assets/icon.svg'), isTrue);
      expect(staysInsideRoot(r'C:\dest', r'..\other'), isFalse);
    });
  });

  group('symbolic links', () {
    test('a symlink entry is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[
          const ForgedEntry('link', content: '/etc/passwd', mode: 0xa1ff),
        ],
      );
      expect(codes(report), contains(DiagnosticCodes.entrySymlink));
    });

    test('a plain file with the same name is not', () async {
      final Report report =
          await verifyEntries(<ForgedEntry>[const ForgedEntry('link')]);
      expect(codes(report), isNot(contains(DiagnosticCodes.entrySymlink)));
    });
  });

  group('size and count caps', () {
    test('an entry over the per-file cap is rejected on its header', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[
          ForgedEntry('big.bin', declaredSize: kMaxEntrySizeBytes + 1),
        ],
      );
      expect(codes(report), contains(DiagnosticCodes.entryTooLarge));
    });

    test('an entry at exactly the per-file cap is allowed', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[ForgedEntry('big.bin', declaredSize: kMaxEntrySizeBytes)],
      );
      expect(codes(report), isNot(contains(DiagnosticCodes.entryTooLarge)));
    });

    test('a bundle over the total cap is rejected', () async {
      const int each = 60 * 1024 * 1024; // each under the per-file cap
      final Report report = await verifyEntries(
        <ForgedEntry>[
          for (var i = 0; i < 5; i++)
            ForgedEntry('part$i.bin', declaredSize: each),
        ],
      );
      expect(codes(report), contains(DiagnosticCodes.archiveTooLarge));
      expect(codes(report), isNot(contains(DiagnosticCodes.entryTooLarge)));
    });

    test('more than 10,000 entries is rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[
          for (var i = 0; i <= kMaxEntryCount; i++) ForgedEntry('f$i.txt'),
        ],
      );
      expect(codes(report), contains(DiagnosticCodes.archiveTooManyEntries));
    });

    test('an empty archive is rejected', () async {
      final Report report = await verifyEntries(<ForgedEntry>[]);
      expect(codes(report), contains(DiagnosticCodes.archiveEmpty));
    });
  });

  group('other malformed archives', () {
    test('two entries unpacking to the same path are rejected', () async {
      final Report report = await verifyEntries(
        <ForgedEntry>[
          const ForgedEntry('assets/icon.svg'),
          const ForgedEntry('./assets/icon.svg'),
        ],
      );
      expect(codes(report), contains(DiagnosticCodes.entryDuplicate));
    });

    test('something that is not a ZIP is rejected without an exception',
        () async {
      final Report report = await const BundleVerifier().verify(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
        target: 'garbage.swayveplugin',
      );
      expect(codes(report), contains(DiagnosticCodes.archiveUnreadable));
    });

    test('a hostile archive never gets as far as its contents', () async {
      // Only the safety diagnostics are reported: nothing was inflated, so no
      // integrity or manifest diagnostics can appear.
      final Report report =
          await verifyEntries(<ForgedEntry>[const ForgedEntry('/etc/passwd')]);
      expect(
        codes(report),
        everyElement(startsWith('entry_')),
      );
    });
  });
}
