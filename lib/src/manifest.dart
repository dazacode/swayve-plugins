import 'semver.dart';

/// A typed, forgiving view over a decoded `plugin.json`.
///
/// Every accessor returns `null` or an empty collection when the underlying
/// value is absent or the wrong shape, because the cross-field rules run after
/// the structural pass and must not crash on a manifest the structural pass has
/// already complained about.
final class PluginManifest {
  /// Wraps [json], which is whatever `plugin.json` decoded to.
  const PluginManifest(this.json);

  /// The decoded manifest object, or an empty map if the document was not one.
  final Map<String, Object?> json;

  /// Wraps [value] if it is a JSON object, otherwise an empty manifest.
  factory PluginManifest.from(Object? value) => PluginManifest(
        value is Map<String, Object?> ? value : const <String, Object?>{},
      );

  T? _get<T>(String key) {
    final Object? value = json[key];
    return value is T ? value : null;
  }

  /// `schemaVersion`.
  int? get schemaVersion => _get<int>('schemaVersion');

  /// `id`.
  String? get id => _get<String>('id');

  /// `name`.
  String? get name => _get<String>('name');

  /// `version`, still as written.
  String? get versionString => _get<String>('version');

  /// `version`, parsed, or `null` if it is not strict SemVer.
  SemVer? get version {
    final String? raw = versionString;
    return raw == null ? null : SemVer.tryParse(raw);
  }

  /// `swayvePluginApi`.
  int? get swayvePluginApi => _get<int>('swayvePluginApi');

  /// `minimumSwayveVersion`, still as written.
  String? get minimumSwayveVersionString =>
      _get<String>('minimumSwayveVersion');

  /// `runtime`.
  String? get runtime => _get<String>('runtime');

  /// `entrypoint`.
  String? get entrypoint => _get<String>('entrypoint');

  /// `icon`.
  String? get icon => _get<String>('icon');

  /// `author.name`.
  String? get authorName {
    final Object? author = json['author'];
    if (author is Map<String, Object?>) {
      final Object? name = author['name'];
      return name is String ? name : null;
    }
    return null;
  }

  /// Whether a `source` object is present at all.
  ///
  /// Distinct from every accessor below returning nothing: a plugin that
  /// declared no source and a plugin that declared an empty one are different
  /// claims, and only the second is worth a diagnostic.
  bool get hasSourceObject => json['source'] is Map<String, Object?>;

  /// `source.sourceId`.
  String? get sourceId => _sourceField<String>('sourceId');

  /// `source.displayName`.
  String? get sourceDisplayName => _sourceField<String>('displayName');

  /// `source.iconName`.
  String? get sourceIconName => _sourceField<String>('iconName');

  /// `source.availability`.
  String? get sourceAvailability => _sourceField<String>('availability');

  /// `source.contentTypes`, keeping only well-formed entries.
  List<String> get sourceContentTypes {
    final List<Object?>? types = _sourceField<List<Object?>>('contentTypes');
    if (types == null) {
      return const <String>[];
    }
    return types.whereType<String>().toList(growable: false);
  }

  T? _sourceField<T>(String key) {
    final Object? source = json['source'];
    if (source is Map<String, Object?>) {
      final Object? value = source[key];
      return value is T ? value : null;
    }
    return null;
  }

  /// `platforms`, keeping only well-formed entries.
  List<String> get platforms => _stringList('platforms');

  /// `capabilities`, keeping only well-formed entries.
  List<String> get capabilities => _stringList('capabilities');

  /// `permissions`, keeping only well-formed entries.
  List<String> get permissions => _stringList('permissions');

  /// `keywords`, keeping only well-formed entries.
  List<String> get keywords => _stringList('keywords');

  /// `network.hosts`, keeping only well-formed entries.
  List<String> get networkHosts {
    final Object? network = json['network'];
    if (network is Map<String, Object?>) {
      final Object? hosts = network['hosts'];
      if (hosts is List<Object?>) {
        return hosts.whereType<String>().toList(growable: false);
      }
    }
    return const <String>[];
  }

  /// Whether `network` is present at all.
  bool get hasNetworkObject => json['network'] is Map<String, Object?>;

  /// `session_capture.hosts`, keeping only well-formed entries.
  List<String> get sessionCaptureHosts {
    final Object? sessionCapture = json['session_capture'];
    if (sessionCapture is Map<String, Object?>) {
      final Object? hosts = sessionCapture['hosts'];
      if (hosts is List<Object?>) {
        return hosts.whereType<String>().toList(growable: false);
      }
    }
    return const <String>[];
  }

  /// `session_capture.capture`, keeping only well-formed entries.
  ///
  /// Each entry is the raw object, unvalidated: rule 12 is what checks that
  /// `from` is in [kSessionCaptureSources] and that `as_secret` names a
  /// declared `secret` setting.
  List<Map<String, Object?>> get sessionCaptureEntries {
    final Object? sessionCapture = json['session_capture'];
    if (sessionCapture is Map<String, Object?>) {
      final Object? capture = sessionCapture['capture'];
      if (capture is List<Object?>) {
        return capture
            .whereType<Map<String, Object?>>()
            .toList(growable: false);
      }
    }
    return const <Map<String, Object?>>[];
  }

  /// Whether `session_capture` is present at all.
  bool get hasSessionCaptureObject =>
      json['session_capture'] is Map<String, Object?>;

  /// `media.<flag>`, or `false` when absent. All three default to `false`.
  bool mediaFlag(String flag) {
    final Object? media = json['media'];
    if (media is Map<String, Object?>) {
      return media[flag] == true;
    }
    return false;
  }

  /// `settings`, keeping only entries that are objects.
  List<Map<String, Object?>> get settings {
    final Object? settings = json['settings'];
    if (settings is List<Object?>) {
      return settings.whereType<Map<String, Object?>>().toList(growable: false);
    }
    return const <Map<String, Object?>>[];
  }

  /// Indices into `settings` paired with the descriptor, so a rule can point at
  /// the right element even when some elements were not objects.
  Iterable<(int, Map<String, Object?>)> get indexedSettings sync* {
    final Object? settings = json['settings'];
    if (settings is! List<Object?>) {
      return;
    }
    for (var i = 0; i < settings.length; i++) {
      final Object? item = settings[i];
      if (item is Map<String, Object?>) {
        yield (i, item);
      }
    }
  }

  /// The path-valued fields the manifest declares, as pointer/value pairs.
  ///
  /// Rule 10 walks this rather than naming `icon` directly, so a future
  /// path-valued field is covered the moment it is added here.
  Iterable<(String, String)> get pathFields sync* {
    final String? iconPath = icon;
    if (iconPath != null) {
      yield ('/icon', iconPath);
    }
  }

  List<String> _stringList(String key) {
    final Object? value = json[key];
    if (value is List<Object?>) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }
}
