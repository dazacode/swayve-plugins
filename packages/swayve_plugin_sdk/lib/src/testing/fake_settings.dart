import 'dart:async';

import '../host/settings.dart';

/// A [SwayveSettingsView] backed by a plain map.
///
/// Mirrors the real host's forgiving behaviour: asking for a setting that is
/// absent, or asking for it as the wrong type, returns `null` rather than
/// throwing, because a manifest change must never crash a running plugin.
final class FakeSwayveSettingsView implements SwayveSettingsView {
  /// Creates a view over [values].
  FakeSwayveSettingsView([Map<String, Object?> values = const {}])
      : _values = Map<String, Object?>.of(values);

  final Map<String, Object?> _values;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Sets [settingId] to [value] and notifies listeners, exactly as the host
  /// does when the user edits a setting.
  void set(String settingId, Object? value) {
    _values[settingId] = value;
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Closes the change stream. Call it in a test's teardown.
  Future<void> close() => _changes.close();

  @override
  T? value<T>(String settingId) {
    final value = _values[settingId];
    return value is T ? value : null;
  }

  @override
  Stream<void> get changes => _changes.stream;
}
