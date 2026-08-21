import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../host/session_capture.dart';
import 'in_memory_stores.dart';

/// One presentation a [FakeSwayveSessionCaptureController] was asked to make.
@immutable
final class RecordedSessionCapturePresentation {
  /// Records a presentation.
  const RecordedSessionCapturePresentation({required this.start, this.timeout});

  /// The URL the plugin asked to present.
  final Uri start;

  /// The timeout the plugin asked for, if any.
  final Duration? timeout;

  @override
  String toString() => 'RecordedSessionCapturePresentation($start)';
}

/// A scripted [SwayveSessionCaptureController] for plugin unit tests.
///
/// Script what the user "does" exactly as with `FakeSwayveWebViewController`:
/// [enqueueNavigation] replays a sequence of URLs through the plugin's own
/// `isComplete` predicate; when one matches, the secrets scripted alongside
/// it (via [enqueueNavigation]'s `capturedSecrets`) are written into
/// [credentials] and the call resolves as
/// [SwayveSessionCaptureOutcome.succeeded]. [enqueueDismissal] simulates the
/// user backing out, and [enqueueTimeout] simulates a flow that never
/// finishes.
final class FakeSwayveSessionCaptureController
    implements SwayveSessionCaptureController {
  /// Creates a controller with nothing scripted, writing captured secrets
  /// into [credentials].
  FakeSwayveSessionCaptureController(this.credentials);

  /// The in-memory credential store a successful capture writes into —
  /// normally the same instance backing the fake context's `credentials`.
  final InMemorySwayveCredentialStore credentials;

  final List<_ScriptedCapture?> _script = <_ScriptedCapture?>[];
  final List<RecordedSessionCapturePresentation> _presentations =
      <RecordedSessionCapturePresentation>[];
  int _timeouts = 0;

  /// Every presentation requested so far, in order.
  List<RecordedSessionCapturePresentation> get presentations =>
      List.unmodifiable(_presentations);

  /// Queues the URLs the web view will navigate to during the next
  /// presentation.
  ///
  /// The first one the plugin's `isComplete` accepts completes the
  /// presentation. When it does, [capturedSecrets] — a map of credential-store
  /// key to value — is written into [credentials], mirroring what the real
  /// host would extract per the manifest's `session_capture` block. If none
  /// of [urls] is accepted, the presentation resolves as a dismissal.
  void enqueueNavigation(
    List<Uri> urls, {
    Map<String, String> capturedSecrets = const {},
  }) =>
      _script.add(_ScriptedCapture(urls, capturedSecrets));

  /// Queues a presentation the user dismisses without completing.
  void enqueueDismissal() => _script.add(null);

  /// Queues a presentation that throws `SwayvePluginTimeoutException`.
  void enqueueTimeout() {
    _timeouts++;
    _script.add(const _ScriptedCapture(<Uri>[], <String, String>{}));
  }

  @override
  Future<SwayveSessionCaptureResult> presentForSessionCapture(
    Uri start, {
    required bool Function(Uri url) isComplete,
    Duration? timeout,
  }) async {
    _presentations.add(
      RecordedSessionCapturePresentation(start: start, timeout: timeout),
    );
    if (_script.isEmpty) {
      throw StateError(
        'FakeSwayveSessionCaptureController: nothing scripted for $start. '
        'Call enqueueNavigation/enqueueDismissal/enqueueTimeout first.',
      );
    }
    final scripted = _script.removeAt(0);
    if (scripted == null) return SwayveSessionCaptureResult.dismissed;
    if (scripted.urls.isEmpty && _timeouts > 0) {
      _timeouts--;
      throw SwayvePluginTimeoutException(
        'Simulated session capture timeout.',
        limit: timeout,
      );
    }
    for (final url in scripted.urls) {
      if (isComplete(url)) {
        for (final entry in scripted.capturedSecrets.entries) {
          await credentials.writeSecret(entry.key, entry.value);
        }
        return SwayveSessionCaptureResult(
          outcome: SwayveSessionCaptureOutcome.succeeded,
          completionUrl: url,
        );
      }
    }
    return SwayveSessionCaptureResult.dismissed;
  }
}

@immutable
class _ScriptedCapture {
  const _ScriptedCapture(this.urls, this.capturedSecrets);

  final List<Uri> urls;
  final Map<String, String> capturedSecrets;
}
