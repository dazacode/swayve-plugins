import 'diagnostics.dart';
import 'json_source.dart';
import 'schema_spec.dart';

/// Walks a decoded JSON value against a [TypeSpec] and reports what does not
/// fit.
///
/// This is a focused evaluator, not a general JSON Schema engine: it implements
/// exactly the keyword set `schema/swayve-plugin.schema.json` uses, which keeps
/// the tools free of a schema-validator dependency and keeps every failure
/// phrased for a plugin author rather than for a schema author.
final class StructuralValidator {
  /// Creates a validator that writes into [sink].
  StructuralValidator(this._sink);

  final DiagnosticSink _sink;

  /// Checks [value] against [spec], rooted at [pointer].
  void check(Object? value, TypeSpec spec, {String pointer = ''}) {
    switch (spec) {
      case ObjectSpec():
        _object(value, spec, pointer);
      case ArraySpec():
        _array(value, spec, pointer);
      case StringSpec():
        _string(value, spec, pointer);
      case IntSpec():
        _int(value, spec, pointer);
      case BoolSpec():
        if (value is! bool) {
          _wrongType(value, spec, pointer);
        }
      case ScalarUnionSpec():
        if (!spec.jsonTypes.contains(jsonTypeOf(value))) {
          _wrongType(value, spec, pointer);
        }
    }
  }

  void _object(Object? value, ObjectSpec spec, String pointer) {
    if (value is! Map<String, Object?>) {
      _wrongType(value, spec, pointer);
      return;
    }
    for (final String name in spec.required) {
      if (!value.containsKey(name)) {
        _sink.error(
          DiagnosticCodes.fieldRequired,
          '${_label(pointer, name)}: required field is missing',
          pointer: joinPointer(pointer, name),
        );
      }
    }
    for (final MapEntry<String, Object?> entry in value.entries) {
      final TypeSpec? child = spec.properties[entry.key];
      final String childPointer = joinPointer(pointer, entry.key);
      if (child == null) {
        _sink.error(
          DiagnosticCodes.fieldUnknown,
          '${_label(pointer, entry.key)}: unknown field; the manifest schema '
          'does not allow extra properties here',
          pointer: childPointer,
        );
        continue;
      }
      check(entry.value, child, pointer: childPointer);
    }
  }

  void _array(Object? value, ArraySpec spec, String pointer) {
    if (value is! List<Object?>) {
      _wrongType(value, spec, pointer);
      return;
    }
    final int? min = spec.minItems;
    final int? max = spec.maxItems;
    if (min != null && value.length < min) {
      _sink.error(
        DiagnosticCodes.fieldLength,
        '${_name(pointer)}: needs at least $min '
        '${min == 1 ? 'entry' : 'entries'}, found ${value.length}',
        pointer: pointer,
      );
    }
    if (max != null && value.length > max) {
      _sink.error(
        DiagnosticCodes.fieldLength,
        '${_name(pointer)}: allows at most $max '
        '${max == 1 ? 'entry' : 'entries'}, found ${value.length}',
        pointer: pointer,
      );
    }
    if (spec.uniqueItems) {
      final Set<String> seen = <String>{};
      for (var i = 0; i < value.length; i++) {
        final String key = _canonical(value[i]);
        if (!seen.add(key)) {
          _sink.error(
            DiagnosticCodes.fieldDuplicate,
            '${_name(pointer)}: duplicate entry ${_show(value[i])}',
            pointer: joinPointer(pointer, i),
          );
        }
      }
    }
    for (var i = 0; i < value.length; i++) {
      check(value[i], spec.items, pointer: joinPointer(pointer, i));
    }
  }

  void _string(Object? value, StringSpec spec, String pointer) {
    if (value is! String) {
      _wrongType(value, spec, pointer);
      return;
    }
    final List<String>? values = spec.values;
    if (values != null) {
      if (!values.contains(value)) {
        _sink.error(
          DiagnosticCodes.fieldEnum,
          "${_name(pointer)}: '$value' is not one of "
          '${values.map((String v) => "'$v'").join(', ')}',
          pointer: pointer,
        );
      }
      return;
    }
    final int? min = spec.minLength;
    final int? max = spec.maxLength;
    if (min != null && value.length < min) {
      _sink.error(
        DiagnosticCodes.fieldLength,
        '${_name(pointer)}: must be at least $min characters, '
        'found ${value.length}',
        pointer: pointer,
      );
    } else if (max != null && value.length > max) {
      _sink.error(
        DiagnosticCodes.fieldLength,
        '${_name(pointer)}: must be at most $max characters, '
        'found ${value.length}',
        pointer: pointer,
      );
    } else {
      final RegExp? pattern = spec.pattern;
      if (pattern != null && !pattern.hasMatch(value)) {
        _sink.error(
          DiagnosticCodes.fieldPattern,
          "${_name(pointer)}: '$value' does not match the required format "
          '${pattern.pattern}',
          pointer: pointer,
        );
      }
    }
    if (spec.noEmoji && containsEmoji(value)) {
      _sink.error(
        DiagnosticCodes.fieldEmoji,
        '${_name(pointer)}: must not contain emoji',
        pointer: pointer,
      );
    }
  }

  void _int(Object? value, IntSpec spec, String pointer) {
    if (value is! int) {
      _wrongType(value, spec, pointer);
      return;
    }
    final int? min = spec.minimum;
    final int? max = spec.maximum;
    if (min != null && value < min) {
      _sink.error(
        DiagnosticCodes.fieldRange,
        '${_name(pointer)}: must be at least $min, found $value',
        pointer: pointer,
      );
    }
    if (max != null && value > max) {
      _sink.error(
        DiagnosticCodes.fieldRange,
        '${_name(pointer)}: must be at most $max, found $value',
        pointer: pointer,
      );
    }
  }

  void _wrongType(Object? value, TypeSpec spec, String pointer) {
    _sink.error(
      DiagnosticCodes.fieldType,
      '${_name(pointer)}: expected ${spec.typeName}, '
      'found ${jsonTypeOf(value)}',
      pointer: pointer,
    );
  }

  static String _name(String pointer) => pointer.isEmpty
      ? 'plugin.json'
      : pointer.substring(1).replaceAll('/', '.');

  static String _label(String pointer, String field) =>
      _name(joinPointer(pointer, field));

  static String _show(Object? value) =>
      value is String ? "'$value'" : _canonical(value);

  static String _canonical(Object? value) {
    if (value is Map<String, Object?>) {
      final List<String> keys = value.keys.toList()..sort();
      return '{${keys.map((String k) => '$k:${_canonical(value[k])}').join(',')}}';
    }
    if (value is List<Object?>) {
      return '[${value.map(_canonical).join(',')}]';
    }
    return '$value';
  }
}

/// The JSON type name of [value], as diagnostics say it.
String jsonTypeOf(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return 'boolean';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  if (value is String) {
    return 'string';
  }
  if (value is List) {
    return 'array';
  }
  if (value is Map) {
    return 'object';
  }
  return 'value';
}

/// Whether [value] contains a character from the emoji planes.
///
/// Deliberately coarse: it catches the pictographic blocks and the variation
/// selector, which is all the "no emoji" rule is asking for.
bool containsEmoji(String value) {
  for (final int rune in value.runes) {
    final bool isEmoji = (rune >= 0x1f000 && rune <= 0x1ffff) ||
        (rune >= 0x2600 && rune <= 0x27bf) ||
        (rune >= 0x2b00 && rune <= 0x2bff) ||
        rune == 0xfe0f;
    if (isEmoji) {
      return true;
    }
  }
  return false;
}
