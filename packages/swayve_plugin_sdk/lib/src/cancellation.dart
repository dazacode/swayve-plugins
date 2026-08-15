/// A one-way signal that the host has lost interest in an operation.
///
/// Principle 7: a broken plugin must never break Swayve. Cancellation is the
/// cooperative half of that — the host can always abandon a call, but a
/// well-behaved provider stops doing work when asked instead of running to
/// completion and discarding the result.
///
/// What a caller may rely on:
/// * once [isCancelled] is `true` it never becomes `false` again;
/// * [whenCancelled] completes exactly once, and never with an error;
/// * [throwIfCancelled] throws `SwayvePluginCancelledException` and nothing
///   else.
///
/// What an implementer of a provider must guarantee: every method that takes
/// a token checks it before starting expensive work and again after every
/// await point, and surfaces `SwayvePluginCancelledException` promptly rather
/// than returning a partial result.
///
/// Create one in tests with `SwayveCancellationTokenSource` from
/// `package:swayve_plugin_sdk/testing.dart`.
abstract interface class SwayveCancellationToken {
  /// Whether cancellation has already been requested.
  bool get isCancelled;

  /// Completes when cancellation is requested.
  ///
  /// If the token is already cancelled the future is already complete. Use
  /// it to race an in-flight operation, for example with `Future.any`.
  Future<void> get whenCancelled;

  /// Throws `SwayvePluginCancelledException` if cancellation has been
  /// requested, and returns normally otherwise.
  void throwIfCancelled();
}
