import '../host/storage.dart';

/// An in-memory [SwayvePluginStorage] for tests.
///
/// It enforces the same key rule a real host does, so a plugin that would be
/// rejected on a device is rejected here too.
final class InMemorySwayvePluginStorage implements SwayvePluginStorage {
  /// Creates a store, optionally pre-populated with [initial] entries.
  InMemorySwayvePluginStorage([Map<String, String> initial = const {}])
      : _values = Map<String, String>.of(initial);

  final Map<String, String> _values;

  /// A snapshot of everything stored, for assertions.
  Map<String, String> get entries => Map<String, String>.unmodifiable(_values);

  void _checkKey(String key) {
    if (!SwayvePluginStorage.keyPattern.hasMatch(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Storage keys must match ${SwayvePluginStorage.keyPattern.pattern}',
      );
    }
  }

  @override
  Future<String?> read(String key) async {
    _checkKey(key);
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _checkKey(key);
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _checkKey(key);
    _values.remove(key);
  }

  @override
  Future<void> clear() async => _values.clear();
}

/// An in-memory [SwayveCredentialStore] for tests.
///
/// Secrets are kept apart from plugin storage here exactly as they are on a
/// device, so a test can assert that a plugin never wrote a token into the
/// wrong place.
final class InMemorySwayveCredentialStore implements SwayveCredentialStore {
  /// Creates a store, optionally pre-populated with [initial] secrets.
  InMemorySwayveCredentialStore([Map<String, String> initial = const {}])
      : _secrets = Map<String, String>.of(initial);

  final Map<String, String> _secrets;

  /// The keys currently holding a secret.
  ///
  /// Deliberately exposes only the keys: a test asserting on secret *values*
  /// is a test that prints them.
  Set<String> get secretKeys => Set<String>.unmodifiable(_secrets.keys.toSet());

  /// Whether a secret is stored at [key].
  bool hasSecret(String key) => _secrets.containsKey(key);

  @override
  Future<String?> readSecret(String key) async => _secrets[key];

  @override
  Future<void> writeSecret(String key, String value) async {
    _secrets[key] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    _secrets.remove(key);
  }
}
