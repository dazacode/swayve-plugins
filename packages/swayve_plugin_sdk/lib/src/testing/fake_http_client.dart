import 'dart:async';

import 'package:meta/meta.dart';

import '../cancellation.dart';
import '../exceptions.dart';
import '../host/http.dart';

/// One request a [FakeSwayveHttpClient] was asked to make.
@immutable
final class RecordedHttpRequest {
  /// Records a request.
  const RecordedHttpRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.timeout,
    this.multipartFields,
    this.multipartFile,
  });

  /// The HTTP method, upper-cased: `GET` or `POST`.
  final String method;

  /// The requested URL.
  final Uri url;

  /// The headers the plugin asked for.
  final Map<String, String> headers;

  /// The request body, for a POST.
  final Object? body;

  /// The timeout the plugin asked for, if any.
  final Duration? timeout;

  /// The form fields, for a `postMultipart` call. `null` for every other
  /// kind of request.
  final Map<String, String>? multipartFields;

  /// The file, for a `postMultipart` call. `null` for every other kind of
  /// request.
  final SwayveMultipartFile? multipartFile;

  @override
  String toString() => 'RecordedHttpRequest($method $url)';
}

/// A scripted [SwayveHttpClient] for plugin unit tests.
///
/// Queue what the network will "return", run the plugin, then assert on
/// [requests]. Responses are consumed in order, regardless of URL, which
/// keeps a test honest about how many calls its plugin makes.
///
/// It can also fail on purpose: [enqueueError] makes the next call throw,
/// and [enqueueHang] makes it never complete, which is how a test proves a
/// plugin actually honours its own deadlines.
final class FakeSwayveHttpClient implements SwayveHttpClient {
  /// Creates an empty client. Queue something before using it.
  FakeSwayveHttpClient();

  final List<_QueuedResult> _queue = <_QueuedResult>[];
  final List<RecordedHttpRequest> _requests = <RecordedHttpRequest>[];

  /// Every request made so far, in order.
  List<RecordedHttpRequest> get requests => List.unmodifiable(_requests);

  /// The most recent request, or `null` if none has been made.
  RecordedHttpRequest? get lastRequest =>
      _requests.isEmpty ? null : _requests.last;

  /// How many queued results are still unconsumed.
  int get pending => _queue.length;

  /// Queues [response] as the result of the next call.
  void enqueueResponse(SwayveHttpResponse response) =>
      _queue.add(_QueuedResult.response(response));

  /// Queues a JSON body as the result of the next call.
  void enqueueJson(Object? json, {int statusCode = 200}) => enqueueResponse(
        SwayveHttpResponse.json(json, statusCode: statusCode),
      );

  /// Queues a plain-text body as the result of the next call.
  void enqueueText(String body, {int statusCode = 200}) => enqueueResponse(
        SwayveHttpResponse.text(body, statusCode: statusCode),
      );

  /// Queues [error] to be thrown by the next call.
  ///
  /// Defaults to the transport failure a real host reports when it cannot
  /// reach a service at all.
  void enqueueError([
    Object error = const SwayvePluginUnavailableException(
      'Simulated transport failure.',
    ),
  ]) =>
      _queue.add(_QueuedResult.error(error));

  /// Queues a call that never completes.
  ///
  /// Use it to test that the plugin's own timeout fires. The returned future
  /// completes only if [cancelHangs] is called, so a test that forgets to
  /// impose a deadline will fail rather than hang forever under a test
  /// runner's own timeout.
  void enqueueHang() => _queue.add(const _QueuedResult.hang());

  /// Completes every outstanding hung call with a transport failure.
  ///
  /// Call it in a test's teardown so a pending future cannot outlive the
  /// test.
  void cancelHangs() {
    for (final completer in _hangs) {
      if (!completer.isCompleted) {
        completer.completeError(
          const SwayvePluginUnavailableException('Hung request abandoned.'),
        );
      }
    }
    _hangs.clear();
  }

  /// Forgets every recorded request and queued result.
  void reset() {
    cancelHangs();
    _queue.clear();
    _requests.clear();
  }

  final List<Completer<SwayveHttpResponse>> _hangs =
      <Completer<SwayveHttpResponse>>[];

  @override
  Future<SwayveHttpResponse> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    SwayveCancellationToken? cancel,
  }) =>
      _handle(
        RecordedHttpRequest(
          method: 'GET',
          url: url,
          headers: Map<String, String>.unmodifiable(headers ?? const {}),
          timeout: timeout,
        ),
        cancel,
      );

  @override
  Future<SwayveHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    SwayveCancellationToken? cancel,
  }) =>
      _handle(
        RecordedHttpRequest(
          method: 'POST',
          url: url,
          headers: Map<String, String>.unmodifiable(headers ?? const {}),
          body: body,
          timeout: timeout,
        ),
        cancel,
      );

  @override
  Future<SwayveHttpResponse> postMultipart(
    Uri url, {
    Map<String, String>? headers,
    required Map<String, String> fields,
    required SwayveMultipartFile file,
    Duration? timeout,
    SwayveCancellationToken? cancel,
  }) =>
      _handle(
        RecordedHttpRequest(
          method: 'POST',
          url: url,
          headers: Map<String, String>.unmodifiable(headers ?? const {}),
          timeout: timeout,
          multipartFields: Map<String, String>.unmodifiable(fields),
          multipartFile: file,
        ),
        cancel,
      );

  Future<SwayveHttpResponse> _handle(
    RecordedHttpRequest request,
    SwayveCancellationToken? cancel,
  ) {
    final String method = request.method;
    final Uri url = request.url;
    _requests.add(request);
    cancel?.throwIfCancelled();
    if (_queue.isEmpty) {
      throw StateError(
        'FakeSwayveHttpClient: no queued result for $method $url. '
        'Queue one with enqueueResponse/enqueueJson/enqueueError.',
      );
    }
    final next = _queue.removeAt(0);
    if (next.hangs) {
      final completer = Completer<SwayveHttpResponse>();
      _hangs.add(completer);
      if (cancel != null) {
        unawaited(
          cancel.whenCancelled.then((_) {
            if (!completer.isCompleted) {
              completer.completeError(const SwayvePluginCancelledException());
            }
          }),
        );
      }
      return completer.future;
    }
    final error = next.error;
    if (error != null) return Future<SwayveHttpResponse>.error(error);
    return Future<SwayveHttpResponse>.value(next.response);
  }
}

final class _QueuedResult {
  const _QueuedResult.response(this.response)
      : error = null,
        hangs = false;

  const _QueuedResult.error(this.error)
      : response = null,
        hangs = false;

  const _QueuedResult.hang()
      : response = null,
        error = null,
        hangs = true;

  final SwayveHttpResponse? response;
  final Object? error;
  final bool hangs;
}
