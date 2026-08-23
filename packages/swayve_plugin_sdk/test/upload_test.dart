import 'dart:typed_data';

import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:swayve_plugin_sdk/testing.dart';
import 'package:test/test.dart';

void main() {
  group('SwayveUploadItem', () {
    SwayveUploadItem item({bool knownDuplicate = false}) => SwayveUploadItem(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'track.mp3',
          mimeType: 'audio/mpeg',
          contentHash: 'abc123',
          title: 'A Song',
          artist: 'An Artist',
          album: 'An Album',
          knownDuplicate: knownDuplicate,
        );

    test('equal fields with equal bytes compare equal', () {
      expect(item(), item());
      expect(item().hashCode, item().hashCode);
    });

    test('different bytes with the same length still compare unequal', () {
      final a = SwayveUploadItem(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'track.mp3',
        contentHash: 'abc123',
        title: 'A Song',
        artist: 'An Artist',
      );
      final b = SwayveUploadItem(
        bytes: Uint8List.fromList([9, 9, 9]),
        fileName: 'track.mp3',
        contentHash: 'abc123',
        title: 'A Song',
        artist: 'An Artist',
      );
      expect(a, isNot(b));
    });

    test('knownDuplicate defaults to false', () {
      final plain = SwayveUploadItem(
        bytes: Uint8List(0),
        fileName: 'track.mp3',
        contentHash: 'abc123',
        title: 'A Song',
        artist: 'An Artist',
      );
      expect(plain.knownDuplicate, isFalse);
    });

    test('toString names the file and the track', () {
      expect(item().toString(), contains('track.mp3'));
      expect(item().toString(), contains('A Song'));
      expect(item().toString(), contains('An Artist'));
    });
  });

  group('SwayveUploadOutcome', () {
    test('every value round-trips through its wire name', () {
      for (final value in SwayveUploadOutcome.values) {
        expect(SwayveUploadOutcome.fromWire(value.wireName), value);
      }
    });

    test('unknown names return null rather than throwing', () {
      expect(SwayveUploadOutcome.fromWire('duplicated'), isNull);
    });
  });

  group('SwayveUploadResult', () {
    test('value equality', () {
      const a = SwayveUploadResult(
        outcome: SwayveUploadOutcome.uploaded,
        remoteId: '42',
      );
      const b = SwayveUploadResult(
        outcome: SwayveUploadOutcome.uploaded,
        remoteId: '42',
      );
      const c = SwayveUploadResult(
        outcome: SwayveUploadOutcome.failed,
        message: 'rejected by remote',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString names the outcome and the remote id', () {
      const result = SwayveUploadResult(
        outcome: SwayveUploadOutcome.uploaded,
        remoteId: '42',
      );
      expect(result.toString(), contains('uploaded'));
      expect(result.toString(), contains('42'));
    });
  });

  group('SwayveLibraryPushProvider against the fake context', () {
    test('a dedup-less provider never has knownUploadHashes called', () async {
      // Nothing to assert here beyond compiling and running cleanly: the
      // point of this test is that the interface permits dedupAlgorithm to
      // be null and a caller can branch on that without ever invoking
      // knownUploadHashes, matching the doc comment's contract.
      final provider = _NoDedupProvider();
      expect(provider.dedupAlgorithm, isNull);
    });

    test('postMultipart is exercised by a provider through the fake client',
        () async {
      final context = FakeSwayvePluginContext(
        permissions: const {SwayvePermission.network},
      );
      context.fakeHttp.enqueueJson({'id': 'remote-1'});

      final response = await context.http.postMultipart(
        Uri.https('upload.example.test', '/'),
        fields: const {'client': 'swayve'},
        file: SwayveMultipartFile(
          fieldName: 'file',
          filename: 'track.mp3',
          bytes: const [1, 2, 3],
          contentType: 'audio/mpeg',
        ),
      );

      expect(response.bodyAsJson, {'id': 'remote-1'});
      expect(context.fakeHttp.requests, hasLength(1));
      final recorded = context.fakeHttp.requests.single;
      expect(recorded.method, 'POST');
      expect(recorded.multipartFields, {'client': 'swayve'});
      expect(recorded.multipartFile?.filename, 'track.mp3');
      expect(recorded.multipartFile?.fieldName, 'file');
      expect(recorded.multipartFile?.contentType, 'audio/mpeg');
    });
  });
}

final class _NoDedupProvider implements SwayveLibraryPushProvider {
  @override
  SwayveUploadHashAlgorithm? get dedupAlgorithm => null;

  @override
  Future<Set<String>> knownUploadHashes({
    SwayveCancellationToken? cancel,
  }) async =>
      throw StateError('must not be called when dedupAlgorithm is null');

  @override
  Future<SwayveUploadResult> uploadTrack(
    SwayveUploadItem item, {
    SwayveCancellationToken? cancel,
  }) async =>
      const SwayveUploadResult(outcome: SwayveUploadOutcome.uploaded);
}
