import 'package:meta/meta.dart';

import '../host/logger.dart';

/// The severity of a [RecordedLogEntry].
enum SwayveLogLevel {
  /// Developer-level detail.
  debug,

  /// A notable, expected event.
  info,

  /// Something wrong but survivable.
  warn,

  /// A failure the plugin could not handle.
  error;

  /// The wire spelling of this level.
  String get wireName => name;
}

/// One line a plugin logged.
@immutable
final class RecordedLogEntry {
  /// Records a log line.
  const RecordedLogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// How severe the plugin said it was.
  final SwayveLogLevel level;

  /// The message text.
  final String message;

  /// The attached error, if any.
  final Object? error;

  /// The attached stack trace, if any.
  final StackTrace? stackTrace;

  @override
  String toString() => '[${level.name}] $message';
}

/// A [SwayvePluginLogger] that keeps what it was told, for assertions.
///
/// Useful for proving a plugin reports a degraded upstream rather than
/// failing silently — and, just as importantly, for proving it never logs a
/// token: assert on [messages] with the secret your test injected.
final class RecordingSwayvePluginLogger implements SwayvePluginLogger {
  /// Creates an empty logger.
  RecordingSwayvePluginLogger();

  final List<RecordedLogEntry> _entries = <RecordedLogEntry>[];

  /// Everything logged so far, in order.
  List<RecordedLogEntry> get entries => List.unmodifiable(_entries);

  /// Just the messages, in order.
  List<String> get messages =>
      List.unmodifiable(_entries.map((entry) => entry.message));

  /// The entries logged at [level].
  List<RecordedLogEntry> at(SwayveLogLevel level) => List.unmodifiable(
        _entries.where((entry) => entry.level == level),
      );

  /// Whether any recorded message contains [needle].
  ///
  /// The check a test uses to assert that a secret never reached the log.
  bool contains(String needle) =>
      _entries.any((entry) => entry.message.contains(needle));

  /// Forgets everything recorded so far.
  void clear() => _entries.clear();

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _entries.add(
        RecordedLogEntry(
          level: SwayveLogLevel.debug,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );

  @override
  void info(String message) => _entries.add(
        RecordedLogEntry(level: SwayveLogLevel.info, message: message),
      );

  @override
  void warn(String message, {Object? error, StackTrace? stackTrace}) =>
      _entries.add(
        RecordedLogEntry(
          level: SwayveLogLevel.warn,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _entries.add(
        RecordedLogEntry(
          level: SwayveLogLevel.error,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );
}
