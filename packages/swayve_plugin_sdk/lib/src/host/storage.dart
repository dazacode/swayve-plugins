/// The plugin's own small key-value store.
///
/// Permission: `local_plugin_storage`. The namespace is the plugin's alone:
/// one plugin can neither read nor write another's data, and none of them can
/// reach the user's music files, the Swayve account, or any path on the
/// device. That isolation is the host's to enforce (principle 4).
///
/// It is for preferences, cursors and small caches. It is not a database and
/// not a place for media: a host may cap total size and evict a plugin's
/// storage under pressure, so a plugin must treat every read as possibly
/// returning `null`.
///
/// Keys must match `^[A-Za-z0-9_.-]{1,128}$`; anything else throws
/// `ArgumentError`, synchronously, before any I/O happens.
abstract interface class SwayvePluginStorage {
  /// The pattern every storage key must match.
  static final RegExp keyPattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');

  /// Reads [key], or returns `null` when it was never written or has been
  /// evicted.
  Future<String?> read(String key);

  /// Writes [value] at [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes [key]. Removing a key that does not exist is not an error.
  Future<void> delete(String key);

  /// Removes every key in this plugin's namespace.
  Future<void> clear();
}

/// Secret storage for the plugin's own credentials.
///
/// Permission: `external_auth`. Values go to the host's platform credential
/// store — keychain, keystore, credential manager — never to
/// `SwayvePluginStorage`, never to a log, and never to another plugin.
///
/// Principle 4 again: encryption is not the security model, so this is not a
/// promise that the bytes are unreadable. It is a promise about *who* may
/// ask for them: only the plugin that wrote them, and only while it holds
/// the `external_auth` permission.
abstract interface class SwayveCredentialStore {
  /// Reads the secret at [key], or `null` if there is none.
  Future<String?> readSecret(String key);

  /// Stores [value] at [key], replacing any previous secret.
  Future<void> writeSecret(String key, String value);

  /// Removes the secret at [key]. Removing an absent secret is not an error.
  Future<void> deleteSecret(String key);
}
