/// Defensive JSON reading for the SDK's normalized models.
///
/// Every `fromJson` in this SDK is ultimately parsing a network response that
/// the plugin does not control, so no reader here is allowed to let a
/// `TypeError` escape: malformed input always surfaces as
/// [SwayvePluginMalformedResponseException] with a message that names the
/// owning type and the offending field.
library;

import '../exceptions.dart';
import '../version.dart';

/// Reports malformed input and never returns.
Never malformed(String message, [Object? cause]) =>
    throw SwayvePluginMalformedResponseException(message, cause: cause);

/// Coerces [value] to a JSON object, or reports it as malformed.
///
/// Accepts any `Map` with string keys, because `jsonDecode` produces
/// `Map<String, dynamic>` and hand-built maps are often `Map<String, Object?>`.
Map<String, Object?> asJsonObject(Object? value, String owner) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        malformed('$owner: JSON object has a non-string key ($key).');
      }
      result[key] = entry.value;
    }
    return result;
  }
  malformed('$owner: expected a JSON object but got ${value.runtimeType}.');
}

/// A cursor over one JSON object belonging to one model type.
///
/// Construct it at the top of a `fromJson`, then read fields through it. Each
/// accessor either returns a well-typed value or throws
/// [SwayvePluginMalformedResponseException].
final class JsonReader {
  /// Wraps [json] for a model called [owner].
  JsonReader(this.owner, this.json);

  /// Wraps an untyped [value] that is expected to be a JSON object.
  factory JsonReader.of(Object? value, String owner) =>
      JsonReader(owner, asJsonObject(value, owner));

  /// The model type name used in error messages.
  final String owner;

  /// The underlying JSON object.
  final Map<String, Object?> json;

  Never _bad(String key, Object? value, String expectation) =>
      malformed("$owner.$key: expected $expectation but got '$value'.");

  /// Whether [key] is present with a non-null value.
  bool has(String key) => json[key] != null;

  /// Reads a required string.
  String string(String key) {
    final value = json[key];
    if (value is String) return value;
    _bad(key, value, 'a string');
  }

  /// Reads an optional string. Returns `null` when absent or null.
  String? stringOrNull(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    _bad(key, value, 'a string or null');
  }

  /// Reads a required integer. Accepts a whole-valued double, since JSON
  /// numbers survive some round trips as doubles.
  int integer(String key) {
    final value = _integerOrNull(key);
    if (value == null) _bad(key, json[key], 'an integer');
    return value;
  }

  /// Reads an optional integer.
  int? integerOrNull(String key) {
    if (json[key] == null) return null;
    final value = _integerOrNull(key);
    if (value == null) _bad(key, json[key], 'an integer or null');
    return value;
  }

  int? _integerOrNull(String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is double && value == value.roundToDouble() && value.isFinite) {
      return value.toInt();
    }
    return null;
  }

  /// Reads a boolean, falling back to [orElse] when absent or null.
  bool boolean(String key, {bool orElse = false}) {
    final value = json[key];
    if (value == null) return orElse;
    if (value is bool) return value;
    _bad(key, value, 'a boolean');
  }

  /// Reads a required duration stored as whole milliseconds.
  Duration duration(String key) => Duration(milliseconds: integer(key));

  /// Reads an optional duration stored as whole milliseconds.
  Duration? durationOrNull(String key) {
    final millis = integerOrNull(key);
    return millis == null ? null : Duration(milliseconds: millis);
  }

  /// Reads a required ISO-8601 timestamp.
  DateTime dateTime(String key) {
    final raw = string(key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) _bad(key, raw, 'an ISO-8601 timestamp');
    return parsed;
  }

  /// Reads a required URI.
  Uri uri(String key) {
    final raw = string(key);
    final parsed = Uri.tryParse(raw);
    if (parsed == null) _bad(key, raw, 'a URI');
    return parsed;
  }

  /// Reads an optional URI.
  Uri? uriOrNull(String key) {
    final raw = stringOrNull(key);
    if (raw == null) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) _bad(key, raw, 'a URI or null');
    return parsed;
  }

  /// Reads a required SemVer version stored as a string.
  Version version(String key) {
    final raw = string(key);
    final parsed = Version.tryParse(raw);
    if (parsed == null) _bad(key, raw, 'a SemVer 2.0.0 version');
    return parsed;
  }

  /// Reads a required nested object through [fromJson].
  T object<T>(String key, T Function(Map<String, Object?>) fromJson) {
    final value = json[key];
    if (value == null) _bad(key, value, 'a JSON object');
    return fromJson(asJsonObject(value, '$owner.$key'));
  }

  /// Reads an optional nested object through [fromJson].
  T? objectOrNull<T>(String key, T Function(Map<String, Object?>) fromJson) {
    final value = json[key];
    if (value == null) return null;
    return fromJson(asJsonObject(value, '$owner.$key'));
  }

  /// Reads a list of nested objects, defaulting to empty when absent.
  List<T> objectList<T>(
    String key,
    T Function(Map<String, Object?>) fromJson,
  ) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) _bad(key, value, 'a JSON array');
    final result = <T>[];
    for (final element in value) {
      result.add(fromJson(asJsonObject(element, '$owner.$key[]')));
    }
    return List<T>.unmodifiable(result);
  }

  /// Reads a list of strings, defaulting to empty when absent.
  List<String> stringList(String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) _bad(key, value, 'a JSON array of strings');
    final result = <String>[];
    for (final element in value) {
      if (element is! String) _bad(key, element, 'a JSON array of strings');
      result.add(element);
    }
    return List<String>.unmodifiable(result);
  }

  /// Reads a map of string keys to strings, defaulting to empty when absent.
  Map<String, String> stringMap(String key) {
    final value = json[key];
    if (value == null) return const {};
    final object = asJsonObject(value, '$owner.$key');
    final result = <String, String>{};
    for (final entry in object.entries) {
      final entryValue = entry.value;
      if (entryValue is! String) {
        _bad(key, entryValue, 'a JSON object of strings');
      }
      result[entry.key] = entryValue;
    }
    return Map<String, String>.unmodifiable(result);
  }

  /// Reads a free-form provider-specific map, defaulting to empty.
  ///
  /// The host never interprets these values, so they are not type-checked
  /// beyond being a JSON object.
  Map<String, Object?> extra(String key) {
    final value = json[key];
    if (value == null) return const {};
    return Map<String, Object?>.unmodifiable(
      asJsonObject(value, '$owner.$key'),
    );
  }

  /// Reads a required enum value through its `fromWire` function.
  T enumValue<T>(String key, T? Function(String) fromWire) {
    final raw = string(key);
    final value = fromWire(raw);
    if (value == null) _bad(key, raw, 'a known $T value');
    return value;
  }

  /// Reads an optional enum value through its `fromWire` function.
  T? enumValueOrNull<T>(String key, T? Function(String) fromWire) {
    final raw = stringOrNull(key);
    if (raw == null) return null;
    final value = fromWire(raw);
    if (value == null) _bad(key, raw, 'a known $T value or null');
    return value;
  }

  /// Reads a set of enum values, defaulting to empty when absent.
  ///
  /// An unknown member is malformed rather than silently dropped: a host that
  /// quietly ignored an unrecognised capability would grant a plugin less
  /// than its manifest promised without telling anyone.
  Set<T> enumSet<T>(String key, T? Function(String) fromWire) {
    final raw = stringList(key);
    final result = <T>{};
    for (final name in raw) {
      final value = fromWire(name);
      if (value == null) _bad(key, name, 'a known $T value');
      result.add(value);
    }
    return Set<T>.unmodifiable(result);
  }
}

/// Serializes a duration as whole milliseconds, or `null`.
int? durationToJson(Duration? duration) => duration?.inMilliseconds;

/// Drops entries whose value is `null` so that the wire form of a model with
/// many optional fields stays small and stable.
Map<String, Object?> pruneNulls(Map<String, Object?> json) {
  final result = <String, Object?>{};
  for (final entry in json.entries) {
    if (entry.value != null) result[entry.key] = entry.value;
  }
  return result;
}
