/// The plugin's channel into the host's diagnostics.
///
/// Every line is attributed to the plugin, so a user reporting a problem
/// carries evidence of which plugin misbehaved — which is what makes
/// principle 7's isolation actionable rather than merely silent.
///
/// The host redacts what it recognises as a secret, but redaction is a safety
/// net, not a licence: **plugins must not log tokens, credentials, signed
/// URLs or personally identifying data.** Nothing here is a permission-gated
/// facility, so this is a contract enforced by review, not by the runtime.
///
/// No permission guards logging.
abstract interface class SwayvePluginLogger {
  /// Records developer-level detail, typically dropped in release builds.
  void debug(String message, {Object? error, StackTrace? stackTrace});

  /// Records a notable, expected event.
  void info(String message);

  /// Records something wrong but survivable — a degraded result, a retry,
  /// a field the provider omitted.
  void warn(String message, {Object? error, StackTrace? stackTrace});

  /// Records a failure the plugin could not handle.
  ///
  /// Logging an error does not report it to the host as a failure: throw a
  /// `SwayvePluginException` for that.
  void error(String message, {Object? error, StackTrace? stackTrace});
}
