import 'dart:convert';

import 'package:meta/meta.dart';

import '../cancellation.dart';
import '../internal/json.dart';

/// The only way a plugin reaches the network.
///
/// Permission: `network`. Principle 3 — plugins talk to their own external
/// services from the user's device, and Swayve hosts no per-plugin proxy —
/// so this is a real client on the device, not a tunnel. What the host adds
/// on top is enforcement: every request is checked against the hostnames the
/// manifest declared, given a deadline, and attributed to the plugin in
/// diagnostics.
///
/// What a caller may rely on:
/// * a request to a host the manifest did not declare fails rather than
///   silently succeeding;
/// * a request that outlives its deadline throws
///   `SwayvePluginTimeoutException`;
/// * a cancelled request throws `SwayvePluginCancelledException`;
/// * a non-2xx status is returned as a response, not thrown — HTTP-level
///   failures are the plugin's to interpret.
///
/// Transport failures (DNS, TLS, connection reset) throw
/// `SwayvePluginUnavailableException`.
abstract interface class SwayveHttpClient {
  /// Performs a GET request.
  ///
  /// [timeout] defaults to `SwayveTimeouts.request` or the manifest's
  /// `timeouts.requestMs` when it declares one.
  Future<SwayveHttpResponse> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    SwayveCancellationToken? cancel,
  });

  /// Performs a POST request.
  ///
  /// [body] may be a `String`, a `List<int>`, or a JSON-encodable structure;
  /// the host encodes anything else as JSON and sets a matching
  /// `content-type` if the caller did not.
  Future<SwayveHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    SwayveCancellationToken? cancel,
  });
}

/// One HTTP response, already fully read.
///
/// Responses are buffered rather than streamed: plugins fetch metadata and
/// short payloads, and media bytes are the host's player's business, not the
/// plugin's.
@immutable
final class SwayveHttpResponse {
  /// Creates a response.
  const SwayveHttpResponse({
    required this.statusCode,
    this.headers = const {},
    this.bodyBytes = const [],
  });

  /// Creates a response whose body is [body] encoded as UTF-8.
  ///
  /// Convenient for tests and for hosts whose transport already decoded the
  /// body.
  factory SwayveHttpResponse.text(
    String body, {
    int statusCode = 200,
    Map<String, String> headers = const {},
  }) =>
      SwayveHttpResponse(
        statusCode: statusCode,
        headers: headers,
        bodyBytes: utf8.encode(body),
      );

  /// Creates a response whose body is [json] encoded as UTF-8 JSON, with a
  /// `content-type` of `application/json`.
  factory SwayveHttpResponse.json(
    Object? json, {
    int statusCode = 200,
    Map<String, String> headers = const {},
  }) =>
      SwayveHttpResponse(
        statusCode: statusCode,
        headers: {'content-type': 'application/json', ...headers},
        bodyBytes: utf8.encode(jsonEncode(json)),
      );

  /// The HTTP status code.
  final int statusCode;

  /// The response headers, with lower-cased names.
  final Map<String, String> headers;

  /// The raw response body.
  final List<int> bodyBytes;

  /// Whether [statusCode] is in the 2xx range.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// The body decoded as UTF-8, with malformed sequences replaced.
  ///
  /// Never throws: a body that is not valid UTF-8 is a data problem for the
  /// plugin to notice, not a crash.
  String get bodyAsString => utf8.decode(bodyBytes, allowMalformed: true);

  /// The body decoded as JSON, or `null` when the body is empty.
  ///
  /// Throws `SwayvePluginMalformedResponseException` when the body is not
  /// valid JSON — which is exactly what a plugin wants to propagate when a
  /// service returns an error page instead of the payload it promised.
  Object? get bodyAsJson {
    if (bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(bodyAsString);
    } on FormatException catch (error) {
      return malformed(
        'SwayveHttpResponse: body is not valid JSON.',
        error,
      );
    }
  }

  @override
  String toString() =>
      'SwayveHttpResponse($statusCode, ${bodyBytes.length} bytes)';
}
