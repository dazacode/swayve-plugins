/// Read access to the settings the user configured for this plugin.
///
/// Principle 5: the host renders the settings UI, from the `settings` block
/// the manifest declared. A plugin never draws its own settings page and
/// never writes a setting — it reads what the user chose and reacts.
///
/// No permission guards this: a plugin's own declared settings are not
/// privileged data.
abstract interface class SwayveSettingsView {
  /// The current value of [settingId], or `null` when the user has not set
  /// it and the manifest declared no default.
  ///
  /// [T] must match the declared setting type: `String` for `string`,
  /// `select` and `secret`; `bool` for `bool`; `int` for `int`. Asking for
  /// the wrong type returns `null` rather than throwing, so that a manifest
  /// change cannot crash a running plugin.
  ///
  /// A `secret` setting reads back as the stored value for the plugin that
  /// owns it, and must never be logged.
  T? value<T>(String settingId);

  /// Fires whenever any of this plugin's settings changes.
  ///
  /// The event carries no payload: re-read what you need through [value].
  /// A plugin that caches settings must listen here, because the user can
  /// change them while the plugin is running.
  Stream<void> get changes;
}
