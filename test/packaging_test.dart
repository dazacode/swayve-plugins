import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

const String _fixture = 'test/fixtures/plugins/demo_source';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('swayve_pkg_');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  group('determinism', () {
    test('packaging the same plugin twice is byte-identical', () async {
      final BuiltBundle first = await const Packager().build(_fixture);
      final BuiltBundle second = await const Packager().build(_fixture);

      expect(first.report.diagnostics, isEmpty);
      expect(first.bytes, isNotNull);
      expect(
        second.bytes,
        orderedEquals(first.bytes!),
        reason: 'packaging must not depend on the machine that ran it',
      );
      expect(second.digest, first.digest);
    });

    test('a CRLF checkout produces the same bundle as an LF one', () async {
      final String lf = _copyFixture(temp, 'lf', lineEnding: '\n');
      final String crlf = _copyFixture(temp, 'crlf', lineEnding: '\r\n');

      final BuiltBundle fromLf = await const Packager().build(lf);
      final BuiltBundle fromCrlf = await const Packager().build(crlf);

      expect(fromLf.bytes, isNotNull);
      expect(fromCrlf.bytes, orderedEquals(fromLf.bytes!));
    });

    test('every entry carries the fixed timestamp and mode', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final ZipDecoder decoder = ZipDecoder();
      decoder.decodeBytes(built.bytes!);
      for (final ZipFileHeader header in decoder.directory.fileHeaders) {
        expect(header.lastModifiedFileDate, 0x0021, reason: '1980-01-01');
        expect(header.lastModifiedFileTime, 0, reason: '00:00:00');
        expect(
          (header.externalFileAttributes ?? 0) >> 16,
          kFixedEntryMode,
          reason: 'no ownership or execute bits travel',
        );
      }
    });

    test('entries are sorted by path', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final ZipDecoder decoder = ZipDecoder();
      decoder.decodeBytes(built.bytes!);
      final List<String> names = decoder.directory.fileHeaders
          .map((ZipFileHeader h) => h.filename)
          .toList();
      final List<String> sorted = List<String>.of(names)
        ..sort(compareBundlePaths);
      expect(names, orderedEquals(sorted));
    });
  });

  group('bundle contents', () {
    late BuiltBundle built;
    late Map<String, Uint8List> members;

    setUp(() async {
      built = await const Packager().build(_fixture);
      members = _membersOf(built.bytes!);
    });

    test('carries exactly the members the format calls for', () {
      expect(members.keys, contains('plugin.json'));
      expect(members.keys, contains('integrity.json'));
      expect(members.keys, contains('signature.json'));
      expect(members.keys, contains('assets/icon.svg'));
      expect(members.keys, contains('licenses/LICENSE'));
      expect(members.keys, contains('payload/lib/demo_source.dart'));
      expect(members.keys, contains('payload/pubspec.yaml'));
      expect(members.keys, contains('payload/README.md'));
      expect(
        members.keys.any((String k) => k.contains('.dart_tool')),
        isFalse,
        reason: 'build detritus never travels',
      );
      expect(
        members.keys.any((String k) => k.startsWith('test/')),
        isFalse,
        reason: 'the plugin test suite is not part of the shipped bundle',
      );
    });

    test('plugin.json matches the source manifest', () {
      final Uint8List source =
          File(p.join(_fixture, 'plugin.json')).readAsBytesSync();
      expect(
        members['plugin.json'],
        orderedEquals(normalizeMemberBytes('plugin.json', source)),
      );
    });

    test('the digest is the documented canonical string, hashed', () {
      final Map<String, String> hashes = <String, String>{
        for (final MapEntry<String, Uint8List> e in members.entries)
          if (!kDigestExcludedMembers.contains(e.key))
            e.key: sha256Hex(e.value),
      };
      final List<String> paths = hashes.keys.toList()..sort(compareBundlePaths);
      final String canonical =
          paths.map((String path) => '$path\n${hashes[path]}\n').join();
      expect(canonicalDigestInput(hashes), canonical);
      expect(built.digest, sha256Hex(utf8.encode(canonical)));
    });

    test('integrity.json lists every member except itself and the signature',
        () {
      final Map<String, Object?> integrity = jsonDecode(
        utf8.decode(members['integrity.json']!),
      )! as Map<String, Object?>;
      expect(integrity['algorithm'], 'sha256');
      expect(integrity['generator'], kGeneratorId);
      expect(integrity['digest'], built.digest);
      final Map<String, Object?> files =
          integrity['files']! as Map<String, Object?>;
      expect(files.keys, isNot(contains('integrity.json')));
      expect(files.keys, isNot(contains('signature.json')));
      expect(
        files.keys.toSet(),
        members.keys.toSet().difference(kDigestExcludedMembers),
      );
      for (final MapEntry<String, Object?> entry in files.entries) {
        expect(entry.value, sha256Hex(members[entry.key]!));
      }
    });

    test('an unsigned bundle says so plainly', () {
      final Map<String, Object?> signature = jsonDecode(
        utf8.decode(members['signature.json']!),
      )! as Map<String, Object?>;
      expect(signature, <String, Object?>{
        'signed': false,
        'algorithm': 'none',
      });
      expect(built.signed, isFalse);
    });
  });

  group('refusing to package', () {
    test('a plugin with an empty licenses/ is not packaged', () async {
      final BuiltBundle built =
          await const Packager().build('test/fixtures/plugins/no_licenses');
      expect(
        built.report.diagnostics.map((Diagnostic d) => d.code),
        contains(DiagnosticCodes.licensesEmpty),
      );
      expect(built.bytes, isNull);
    });

    test('a plugin that fails validation is not packaged', () async {
      final BuiltBundle built = await const Packager()
          .build('test/fixtures/plugins/misnamed_directory');
      expect(
        built.report.diagnostics.map((Diagnostic d) => d.code),
        contains(DiagnosticCodes.directoryNameMismatch),
      );
      expect(built.bytes, isNull);
    });

    test('a missing required file is named', () async {
      final String copy = _copyFixture(temp, 'strip');
      File(p.join(copy, 'README.md')).deleteSync();
      final BuiltBundle built = await const Packager().build(copy);
      expect(
        built.report.diagnostics.map((Diagnostic d) => d.message),
        contains(contains('README.md')),
      );
      expect(built.bytes, isNull);
    });

    test('--strict refuses a plugin that only has warnings', () async {
      final String copy = _copyFixture(temp, 'warn');
      final Map<String, Object?> manifest = jsonDecode(
        File(p.join(copy, 'plugin.json')).readAsStringSync(),
      )! as Map<String, Object?>;
      manifest['permissions'] = <String>['network', 'clipboard', 'webview'];
      File(p.join(copy, 'plugin.json')).writeAsStringSync(jsonEncode(manifest));

      final BuiltBundle lenient = await const Packager().build(copy);
      expect(lenient.bytes, isNotNull);
      expect(lenient.report.warningCount, greaterThan(0));

      final BuiltBundle strict =
          await const Packager().build(copy, strict: true);
      expect(strict.bytes, isNull);
    });
  });

  group('writing artifacts', () {
    test('writes the bundle and a sha256 sidecar', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final String out = p.join(temp.path, 'dist');
      final List<String> written = const Packager().writeBundle(built, out);

      expect(written, hasLength(2));
      expect(p.basename(written[0]), 'demo_source-1.0.0.swayveplugin');
      expect(p.basename(written[1]), 'demo_source-1.0.0.sha256');

      final Uint8List onDisk = File(written[0]).readAsBytesSync();
      expect(onDisk, orderedEquals(built.bytes!));
      expect(
        File(written[1]).readAsStringSync(),
        '${sha256Hex(onDisk)}  demo_source-1.0.0.swayveplugin\n',
      );
    });
  });

  group('verification round trip', () {
    test('a freshly packaged bundle verifies clean', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Report report = await const BundleVerifier().verify(
        built.bytes!,
        target: 'demo_source-1.0.0.swayveplugin',
        fileName: 'demo_source-1.0.0.swayveplugin',
      );
      expect(report.errorCount, 0, reason: _codes(report).toString());
      expect(report.warningCount, 0, reason: _codes(report).toString());
      expect(_codes(report), contains(DiagnosticCodes.signatureAbsent));
      expect(
        report.diagnostics
            .firstWhere(
              (Diagnostic d) => d.code == DiagnosticCodes.signatureAbsent,
            )
            .severity,
        Severity.info,
      );
    });

    test('a wrong filename is a warning', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Report report = await const BundleVerifier().verify(
        built.bytes!,
        target: 'x',
        fileName: 'something-else.swayveplugin',
      );
      expect(_codes(report), contains(DiagnosticCodes.bundleNameMismatch));
    });

    test('tampering with a member is caught', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Map<String, Uint8List> members = _membersOf(built.bytes!);
      members['licenses/LICENSE'] =
          Uint8List.fromList(utf8.encode('a different licence\n'));

      final Report report = await const BundleVerifier().verify(
        _repack(members),
        target: 'tampered',
      );
      expect(_codes(report), contains(DiagnosticCodes.integrityHashMismatch));
      expect(_codes(report), contains(DiagnosticCodes.integrityDigestMismatch));
    });

    test('adding an unlisted member is caught', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Map<String, Uint8List> members = _membersOf(built.bytes!)
        ..['payload/lib/backdoor.dart'] =
            Uint8List.fromList(utf8.encode('// smuggled\n'));

      final Report report = await const BundleVerifier().verify(
        _repack(members),
        target: 'tampered',
      );
      expect(_codes(report), contains(DiagnosticCodes.integrityFileUnlisted));
    });

    test('removing a listed member is caught', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Map<String, Uint8List> members = _membersOf(built.bytes!)
        ..remove('assets/icon.svg');

      final Report report = await const BundleVerifier().verify(
        _repack(members),
        target: 'tampered',
      );
      expect(_codes(report), contains(DiagnosticCodes.integrityFileMissing));
    });

    test('a bundle with no licenses/ is rejected', () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Map<String, Uint8List> members = _membersOf(built.bytes!)
        ..remove('licenses/LICENSE');

      final Report report = await const BundleVerifier().verify(
        _repack(members),
        target: 'tampered',
      );
      expect(_codes(report), contains(DiagnosticCodes.licensesEmpty));
    });
  });

  group('signing', () {
    final Uint8List seed = Uint8List.fromList(
      List<int>.generate(32, (int i) => (i * 7 + 3) & 0xff),
    );

    test('a signed bundle verifies, and names the key that signed it',
        () async {
      final BuiltBundle built =
          await const Packager().build(_fixture, signingSeed: seed);
      expect(built.signed, isTrue);

      final Map<String, Object?> signature = jsonDecode(
        utf8.decode(_membersOf(built.bytes!)['signature.json']!),
      )! as Map<String, Object?>;
      expect(signature['signed'], isTrue);
      expect(signature['algorithm'], 'ed25519');
      expect(signature['digest'], built.digest);

      final Uint8List publicKey = await publicKeyForSeed(seed);
      expect(signature['publicKey'], base64.encode(publicKey));
      expect(signature['keyId'], keyIdFor(publicKey));

      final Report report = await BundleVerifier(
        expectedPublicKey: publicKey,
      ).verify(built.bytes!, target: 'signed');
      expect(report.errorCount, 0, reason: _codes(report).toString());
    });

    test('a bundle signed by another key is rejected', () async {
      final BuiltBundle built =
          await const Packager().build(_fixture, signingSeed: seed);
      final Uint8List otherSeed = Uint8List.fromList(List<int>.filled(32, 9));
      final Report report = await BundleVerifier(
        expectedPublicKey: await publicKeyForSeed(otherSeed),
      ).verify(built.bytes!, target: 'signed');
      expect(_codes(report), contains(DiagnosticCodes.signatureKeyMismatch));
    });

    test('a forged signature does not verify', () async {
      final BuiltBundle built =
          await const Packager().build(_fixture, signingSeed: seed);
      final Map<String, Uint8List> members = _membersOf(built.bytes!);
      final Map<String, Object?> signature = jsonDecode(
        utf8.decode(members['signature.json']!),
      )! as Map<String, Object?>;
      final List<int> bytes = base64.decode(signature['signature']! as String);
      bytes[0] ^= 0xff;
      signature['signature'] = base64.encode(bytes);
      members['signature.json'] = encodeBundleJson(signature);

      final Report report =
          await const BundleVerifier().verify(_repack(members), target: 'x');
      expect(_codes(report), contains(DiagnosticCodes.signatureInvalid));
    });

    test('a signature over a different digest is rejected', () async {
      final BuiltBundle built =
          await const Packager().build(_fixture, signingSeed: seed);
      final Map<String, Uint8List> members = _membersOf(built.bytes!);
      final Map<String, Object?> signature = jsonDecode(
        utf8.decode(members['signature.json']!),
      )! as Map<String, Object?>;
      signature['digest'] = sha256Hex(utf8.encode('some other bundle'));
      members['signature.json'] = encodeBundleJson(signature);

      final Report report =
          await const BundleVerifier().verify(_repack(members), target: 'x');
      expect(
        _codes(report),
        contains(DiagnosticCodes.signatureDigestMismatch),
      );
    });

    test('--require-signature turns an unsigned bundle into a failure',
        () async {
      final BuiltBundle built = await const Packager().build(_fixture);
      final Report report = await const BundleVerifier(requireSignature: true)
          .verify(built.bytes!, target: 'x');
      expect(_codes(report), contains(DiagnosticCodes.signatureAbsent));
      expect(report.errorCount, 1);
    });

    test('a key seed can be given as raw bytes, hex or base64', () {
      final Uint8List raw = Uint8List.fromList(List<int>.filled(32, 42));
      final String hex = raw
          .map(
            (int b) => b.toRadixString(16).padLeft(2, '0'),
          )
          .join();
      expect(parseEd25519Seed(raw), orderedEquals(raw));
      expect(parseEd25519Seed(utf8.encode('$hex\n')), orderedEquals(raw));
      expect(
        parseEd25519Seed(utf8.encode('${base64.encode(raw)}\n')),
        orderedEquals(raw),
      );
    });

    test('a key of the wrong length is refused, not truncated', () {
      expect(
        () => parseEd25519Seed(utf8.encode(base64.encode(<int>[1, 2, 3]))),
        throwsA(isA<SigningKeyError>()),
      );
    });
  });
}

List<String> _codes(Report report) =>
    report.diagnostics.map((Diagnostic d) => d.code).toList(growable: false);

Map<String, Uint8List> _membersOf(Uint8List zipBytes) {
  final Archive archive = ZipDecoder().decodeBytes(zipBytes);
  return <String, Uint8List>{
    for (final ArchiveFile file in archive.files)
      if (file.isFile) file.name: Uint8List.fromList(file.content as List<int>),
  };
}

Uint8List _repack(Map<String, Uint8List> members) => encodeDeterministicZip(
      <BundleMember>[
        for (final MapEntry<String, Uint8List> e in members.entries)
          BundleMember(e.key, e.value),
      ],
    );

/// Copies the fixture plugin into [temp]`/`[label]`/demo_source`, optionally
/// rewriting text files to use [lineEnding].
///
/// The leaf directory keeps the fixture's name because rule 7 checks it.
String _copyFixture(Directory temp, String label, {String lineEnding = '\n'}) {
  final String destination = p.join(temp.path, label, 'demo_source');
  Directory(destination).createSync(recursive: true);
  for (final FileSystemEntity entity
      in Directory(_fixture).listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final String relative = p.relative(entity.path, from: _fixture);
    final File target = File(p.join(destination, relative));
    target.parent.createSync(recursive: true);
    if (isTextMember(relative.replaceAll(r'\', '/'))) {
      final String text = entity.readAsStringSync().replaceAll('\r\n', '\n');
      target.writeAsStringSync(text.replaceAll('\n', lineEnding));
    } else {
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
  }
  return destination;
}
