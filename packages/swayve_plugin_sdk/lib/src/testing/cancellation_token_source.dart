import 'dart:async';

import '../cancellation.dart';
import '../exceptions.dart';

/// Creates and controls a [SwayveCancellationToken].
///
/// A host owns one of these per in-flight operation; a test owns one to prove
/// that a provider actually stops when asked. The source is the only thing
/// that can cancel — a provider holding the token can observe cancellation
/// but never cause it.
final class SwayveCancellationTokenSource {
  /// Creates a source whose token has not been cancelled.
  SwayveCancellationTokenSource();

  final Completer<void> _completer = Completer<void>();
  late final SwayveCancellationToken _token = _Token(this);

  /// The token to hand to the operation.
  ///
  /// The same instance every time, so it compares identically across calls.
  SwayveCancellationToken get token => _token;

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// Requests cancellation.
  ///
  /// Idempotent: calling it again does nothing. Everything awaiting
  /// `token.whenCancelled` completes on the next microtask.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

final class _Token implements SwayveCancellationToken {
  _Token(this._source);

  final SwayveCancellationTokenSource _source;

  @override
  bool get isCancelled => _source.isCancelled;

  @override
  Future<void> get whenCancelled => _source._completer.future;

  @override
  void throwIfCancelled() {
    if (isCancelled) {
      throw const SwayvePluginCancelledException();
    }
  }
}
