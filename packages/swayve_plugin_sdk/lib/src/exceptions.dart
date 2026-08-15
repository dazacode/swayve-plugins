import 'enums.dart';

/// The closed set of failures a plugin is allowed to report to the host.
///
/// Principle 7: a broken plugin must never break Swayve. Every host-to-plugin
/// call is expected to either complete, or fail with one of the subtypes of
/// this class. A plugin that throws anything else is still isolated by the
/// host, but it forfeits the ability to explain itself: the host can only
/// treat an unknown error as [SwayvePluginUnavailableException] and show a
/// generic "temporarily unavailable" state.
///
/// The hierarchy is `sealed`, so a host can switch over it exhaustively and
/// the compiler will flag any case it forgot when the SDK adds one. Adding a
/// subtype is therefore a breaking change to the plugin API level.
sealed class SwayvePluginException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  ///
  /// [message] is developer-facing and may be logged; it must never contain
  /// credentials, tokens or any other secret. [cause] is the underlying error
  /// that triggered this failure, if there was one.
  const SwayvePluginException(this.message, {this.cause});

  /// A short, developer-facing description of what went wrong.
  ///
  /// This is not a user-facing string: the host is responsible for turning a
  /// failure into user-readable copy (principle 5, and the lifecycle rules in
  /// the plugin lifecycle documentation).
  final String message;

  /// The underlying error this failure was derived from, if any.
  ///
  /// Implementers should populate this when wrapping a lower-level error so
  /// that host diagnostics keep the original context.
  final Object? cause;

  /// The stable, machine-readable code for this failure kind.
  ///
  /// Hosts and tools may key telemetry and user-facing copy off this value.
  /// It is part of the public contract and does not change for a given
  /// subtype within an API level.
  String get code;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType($code): $message');
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    return buffer.toString();
  }
}

/// The provider cannot serve the request right now.
///
/// Use this for a service outage, an unreachable network, or any transient
/// condition the user can reasonably retry. The host treats it as a soft
/// failure: the plugin stays loaded and the affected surface degrades.
final class SwayvePluginUnavailableException extends SwayvePluginException {
  /// Creates an unavailability failure.
  const SwayvePluginUnavailableException(super.message, {super.cause});

  @override
  String get code => 'plugin_unavailable';
}

/// The operation did not finish inside its deadline.
///
/// A plugin should raise this itself when it knows it has blown a budget from
/// [SwayveTimeouts]. The host applies its own hard deadline regardless, and a
/// breach of the host deadline is reported as
/// [SwayvePluginUnavailableException] rather than as this type.
final class SwayvePluginTimeoutException extends SwayvePluginException {
  /// Creates a timeout failure, optionally recording the [limit] that was hit.
  const SwayvePluginTimeoutException(super.message, {this.limit, super.cause});

  /// The deadline that was exceeded, when the thrower knows it.
  final Duration? limit;

  @override
  String get code => 'plugin_timeout';
}

/// The operation was cancelled through a [SwayveCancellationToken].
///
/// This is not an error condition: the host asked for the work to stop. A
/// provider must surface it promptly rather than finishing the work and
/// discarding the result.
final class SwayvePluginCancelledException extends SwayvePluginException {
  /// Creates a cancellation failure.
  const SwayvePluginCancelledException([
    super.message = 'The operation was cancelled.',
  ]);

  @override
  String get code => 'plugin_cancelled';
}

/// The user must authenticate with the plugin's service before this can work.
///
/// The host reacts by prompting the user to sign in through the plugin's
/// [SwayveAuthProvider]; it never handles the plugin's credentials itself.
final class SwayvePluginAuthRequiredException extends SwayvePluginException {
  /// Creates an authentication-required failure.
  const SwayvePluginAuthRequiredException(
    super.message, {
    super.cause,
  });

  @override
  String get code => 'plugin_auth_required';
}

/// The upstream service is rate limiting the plugin.
///
/// [retryAfter] is a hint the host may use to schedule a retry. A plugin that
/// knows the service's limits should prefer throttling itself over throwing.
final class SwayvePluginRateLimitedException extends SwayvePluginException {
  /// Creates a rate-limit failure, optionally carrying a [retryAfter] hint.
  const SwayvePluginRateLimitedException(
    super.message, {
    this.retryAfter,
    super.cause,
  });

  /// How long the caller should wait before retrying, when known.
  final Duration? retryAfter;

  @override
  String get code => 'plugin_rate_limited';
}

/// A response could not be interpreted.
///
/// Every `fromJson` in this SDK throws this — and never a raw `TypeError` —
/// when its input is not shaped the way the contract requires, because that
/// input ultimately came from a network response the plugin does not control.
final class SwayvePluginMalformedResponseException
    extends SwayvePluginException {
  /// Creates a malformed-response failure.
  const SwayvePluginMalformedResponseException(super.message, {super.cause});

  @override
  String get code => 'plugin_malformed_response';
}

/// The plugin does not implement the requested behaviour.
///
/// Throw this from a provider method a plugin deliberately does not support,
/// rather than returning empty data that the host would mistake for "nothing
/// found".
final class SwayvePluginUnsupportedException extends SwayvePluginException {
  /// Creates an unsupported-operation failure.
  const SwayvePluginUnsupportedException(super.message, {super.cause});

  @override
  String get code => 'plugin_unsupported';
}

/// A context facility was accessed without the permission that guards it.
///
/// Principle 4: permissions, not encryption, are the security model. The host
/// throws this synchronously the moment an undeclared facility is touched, so
/// the failure is attributable to the line that over-reached rather than to
/// some later request.
final class SwayvePermissionDeniedException extends SwayvePluginException {
  /// Creates a permission failure for [permission].
  const SwayvePermissionDeniedException(
    this.permission, {
    String? message,
    super.cause,
  }) : super(message ?? 'Permission denied.');

  /// The permission the plugin would have needed to declare.
  final SwayvePermission permission;

  @override
  String get code => 'permission_denied';

  @override
  String toString() =>
      'SwayvePermissionDeniedException(${permission.wireName}): $message';
}

/// The plugin targets an API level the host cannot speak.
///
/// Raised during the compatibility phase of the plugin lifecycle, before the
/// plugin is initialized. The host turns it into user-readable copy such as
/// `"<Plugin name> requires a newer version of Swayve."`
final class SwayveIncompatibleApiException extends SwayvePluginException {
  /// Creates an API-level mismatch failure.
  ///
  /// [requiredApi] is the level the plugin declared; [actualApi] is the level
  /// the host implements.
  const SwayveIncompatibleApiException({
    required this.requiredApi,
    required this.actualApi,
    String? message,
    super.cause,
  }) : super(
          message ??
              'Plugin requires API level $requiredApi '
                  'but the host implements $actualApi.',
        );

  /// The API level the plugin declared it needs.
  final int requiredApi;

  /// The API level the host actually implements.
  final int actualApi;

  @override
  String get code => 'incompatible_api';
}
