import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../host/webview.dart';

/// One presentation a [FakeSwayveWebViewController] was asked to make.
@immutable
final class RecordedWebViewPresentation {
  /// Records a presentation.
  const RecordedWebViewPresentation({required this.start, this.timeout});

  /// The URL the plugin asked to present.
  final Uri start;

  /// The timeout the plugin asked for, if any.
  final Duration? timeout;

  @override
  String toString() => 'RecordedWebViewPresentation($start)';
}

/// A scripted [SwayveWebViewController] for plugin unit tests.
///
/// Script what the user "does": [enqueueNavigation] replays a sequence of
/// URLs through the plugin's own `isComplete` predicate, so a test exercises
/// the real redirect-matching logic rather than a stubbed answer.
/// [enqueueDismissal] simulates the user backing out, and [enqueueTimeout]
/// simulates a flow that never finishes.
final class FakeSwayveWebViewController implements SwayveWebViewController {
  /// Creates a controller with nothing scripted.
  FakeSwayveWebViewController();

  final List<List<Uri>?> _script = <List<Uri>?>[];
  final List<RecordedWebViewPresentation> _presentations =
      <RecordedWebViewPresentation>[];
  int _timeouts = 0;

  /// Every presentation requested so far, in order.
  List<RecordedWebViewPresentation> get presentations =>
      List.unmodifiable(_presentations);

  /// Queues the URLs the web view will navigate to during the next
  /// presentation.
  ///
  /// The first one the plugin's `isComplete` accepts is returned to it; if
  /// none is accepted, the presentation resolves as a dismissal.
  void enqueueNavigation(List<Uri> urls) => _script.add(List<Uri>.of(urls));

  /// Queues a presentation the user dismisses without completing.
  void enqueueDismissal() => _script.add(null);

  /// Queues a presentation that throws `SwayvePluginTimeoutException`.
  void enqueueTimeout() {
    _timeouts++;
    _script.add(const <Uri>[]);
  }

  @override
  Future<Uri?> presentForResult(
    Uri start, {
    required bool Function(Uri url) isComplete,
    Duration? timeout,
  }) async {
    _presentations.add(
      RecordedWebViewPresentation(start: start, timeout: timeout),
    );
    if (_script.isEmpty) {
      throw StateError(
        'FakeSwayveWebViewController: nothing scripted for $start. '
        'Call enqueueNavigation/enqueueDismissal first.',
      );
    }
    final navigation = _script.removeAt(0);
    if (navigation == null) return null;
    if (navigation.isEmpty && _timeouts > 0) {
      _timeouts--;
      throw SwayvePluginTimeoutException(
        'Simulated web view timeout.',
        limit: timeout,
      );
    }
    for (final url in navigation) {
      if (isComplete(url)) return url;
    }
    return null;
  }
}
