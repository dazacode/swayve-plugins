import 'dart:async';

import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:swayve_plugin_sdk/testing.dart';
import 'package:test/test.dart';

void main() {
  test('a fresh token is not cancelled', () {
    final source = SwayveCancellationTokenSource();
    expect(source.isCancelled, isFalse);
    expect(source.token.isCancelled, isFalse);
    expect(source.token.throwIfCancelled, returnsNormally);
  });

  test('the same token instance is handed out every time', () {
    final source = SwayveCancellationTokenSource();
    expect(identical(source.token, source.token), isTrue);
  });

  test('cancelling flips isCancelled and makes throwIfCancelled throw', () {
    final source = SwayveCancellationTokenSource();
    source.cancel();
    expect(source.isCancelled, isTrue);
    expect(source.token.isCancelled, isTrue);
    expect(
      source.token.throwIfCancelled,
      throwsA(isA<SwayvePluginCancelledException>()),
    );
  });

  test('cancellation is one-way and idempotent', () {
    final source = SwayveCancellationTokenSource()
      ..cancel()
      ..cancel();
    expect(source.isCancelled, isTrue);
  });

  test('whenCancelled completes exactly once, without an error', () async {
    final source = SwayveCancellationTokenSource();
    var completions = 0;
    unawaited(source.token.whenCancelled.then((_) => completions++));
    expect(completions, 0);
    source.cancel();
    await source.token.whenCancelled;
    expect(completions, 1);
  });

  test('whenCancelled on an already-cancelled token is already done', () async {
    final source = SwayveCancellationTokenSource()..cancel();
    await source.token.whenCancelled.timeout(const Duration(seconds: 1));
  });

  test('a provider that checks its token stops on cancellation', () async {
    final source = SwayveCancellationTokenSource();
    final steps = <String>[];

    Future<void> work(SwayveCancellationToken token) async {
      token.throwIfCancelled();
      steps.add('first');
      await Future<void>.delayed(Duration.zero);
      token.throwIfCancelled();
      steps.add('second');
    }

    final future = work(source.token);
    source.cancel();
    await expectLater(
      future,
      throwsA(isA<SwayvePluginCancelledException>()),
    );
    expect(steps, ['first'], reason: 'the second step must not have run');
  });

  test('a hung request can be raced against cancellation', () async {
    final client = FakeSwayveHttpClient()..enqueueHang();
    final source = SwayveCancellationTokenSource();
    final future = client.get(
      Uri.parse('https://example.test/slow'),
      cancel: source.token,
    );
    source.cancel();
    await expectLater(
      future,
      throwsA(isA<SwayvePluginCancelledException>()),
    );
  });

  test('a request made with an already-cancelled token fails fast', () {
    final client = FakeSwayveHttpClient()..enqueueJson({'ok': true});
    final source = SwayveCancellationTokenSource()..cancel();
    expect(
      () => client.get(
        Uri.parse('https://example.test/x'),
        cancel: source.token,
      ),
      throwsA(isA<SwayvePluginCancelledException>()),
    );
    expect(client.pending, 1, reason: 'the queued response is untouched');
  });

  test('a hang can be abandoned in teardown', () async {
    final client = FakeSwayveHttpClient()..enqueueHang();
    final future = client.get(Uri.parse('https://example.test/slow'));
    client.cancelHangs();
    await expectLater(
      future,
      throwsA(isA<SwayvePluginUnavailableException>()),
    );
  });

  test('a plugin can impose its own deadline on a hung request', () async {
    final client = FakeSwayveHttpClient()..enqueueHang();
    Future<SwayveHttpResponse> fetch() => client
        .get(Uri.parse('https://example.test/slow'))
        .timeout(const Duration(milliseconds: 20));
    await expectLater(fetch(), throwsA(isA<TimeoutException>()));
    client.cancelHangs();
  });
}
