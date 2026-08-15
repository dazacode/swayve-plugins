/// The deadlines the host and plugins agree on.
///
/// Principle 7: every host-to-plugin call is timeout-bounded. These are the
/// defaults a plugin should assume when its manifest does not override them
/// with a `timeouts` block. A plugin may finish sooner; it may never assume
/// it will be allowed to run longer.
///
/// The host applies its own hard deadline regardless of what the plugin
/// does, and treats a breach as `SwayvePluginUnavailableException`.
abstract final class SwayveTimeouts {
  /// The budget for a single outbound HTTP request made through
  /// `SwayveHttpClient` when the caller does not pass its own timeout.
  static const Duration request = Duration(seconds: 10);

  /// The budget for one complete provider call, including any retries and
  /// follow-up requests it makes internally.
  static const Duration operation = Duration(seconds: 20);

  /// The budget for `SwayvePlugin.initialize`.
  ///
  /// A plugin that needs longer must return quickly and continue in the
  /// background; a plugin that blocks past this moves to `degraded`.
  static const Duration initialize = Duration(seconds: 8);

  /// The budget for `SwayvePlugin.dispose`.
  ///
  /// Teardown must be fast and must not depend on the network: the host may
  /// be shutting down or reclaiming memory.
  static const Duration dispose = Duration(seconds: 3);
}
