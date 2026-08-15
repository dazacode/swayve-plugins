import 'dart:convert';

/// JSON that would not parse, with the place it gave up.
final class JsonSyntaxError implements Exception {
  /// Creates a syntax error at [line]/[column].
  const JsonSyntaxError(this.message, this.line, this.column);

  /// What the decoder complained about.
  final String message;

  /// One-based line of the failure.
  final int line;

  /// One-based column of the failure.
  final int column;

  @override
  String toString() => '$message (line $line, column $column)';
}

/// A decoded JSON document that remembers where each value came from.
///
/// The value itself comes from `dart:convert`, which is the authority on what
/// the document means. The line index is built by a second, deliberately
/// simple pass over text we already know is valid, so a diagnostic can point a
/// human at `plugin.json:14` instead of at a JSON pointer alone.
final class JsonSource {
  JsonSource._(this.text, this.value, this._lineOfPointer);

  /// The raw document text.
  final String text;

  /// The decoded value: `Map`, `List`, `String`, `num`, `bool` or `null`.
  final Object? value;

  final Map<String, int> _lineOfPointer;

  /// Decodes [text], throwing [JsonSyntaxError] if it is not valid JSON.
  static JsonSource parse(String text) {
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException catch (e) {
      final int offset = e.offset ?? 0;
      final _LineIndex index = _LineIndex(text);
      final (int line, int column) = index.positionOf(offset);
      return throw JsonSyntaxError(_tidy(e.message), line, column);
    }
    final _PointerScanner scanner = _PointerScanner(text);
    scanner.run();
    return JsonSource._(text, value, scanner.lines);
  }

  /// The one-based line [pointer] sits on, or `null` if it is not in the
  /// document.
  int? lineFor(String pointer) => _lineOfPointer[pointer];

  /// The line of [pointer], falling back to the nearest ancestor that is in
  /// the document. A pointer at `/settings/3/label` on a manifest that has no
  /// fourth setting still lands on `/settings`.
  int? nearestLineFor(String pointer) {
    var current = pointer;
    while (true) {
      final int? line = _lineOfPointer[current];
      if (line != null) {
        return line;
      }
      final int slash = current.lastIndexOf('/');
      if (slash < 0) {
        return null;
      }
      current = current.substring(0, slash);
    }
  }

  static String _tidy(String message) {
    // `dart:convert` messages start with "Unexpected character" and friends;
    // they read fine on their own, we just drop the trailing source echo.
    final int at = message.indexOf(' (at ');
    return at < 0 ? message : message.substring(0, at);
  }
}

/// Escapes one path segment for use in an RFC 6901 JSON pointer.
String escapePointerSegment(String segment) =>
    segment.replaceAll('~', '~0').replaceAll('/', '~1');

/// Appends [segment] to [pointer].
String joinPointer(String pointer, Object segment) =>
    '$pointer/${escapePointerSegment('$segment')}';

class _LineIndex {
  _LineIndex(this.text) {
    _starts.add(0);
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) {
        _starts.add(i + 1);
      }
    }
  }

  final String text;
  final List<int> _starts = <int>[];

  (int, int) positionOf(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final int mid = (low + high + 1) ~/ 2;
      if (_starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return (low + 1, offset - _starts[low] + 1);
  }
}

/// Walks text that `jsonDecode` has already accepted, recording the line each
/// JSON pointer starts on. Because the input is known-good this only has to be
/// a structural scan, not a validating parser.
class _PointerScanner {
  _PointerScanner(this.text) : _index = _LineIndex(text);

  final String text;
  final _LineIndex _index;

  /// Pointer to one-based line.
  final Map<String, int> lines = <String, int>{};

  int _pos = 0;

  void run() {
    _value('');
  }

  void _value(String pointer) {
    _skipWhitespace();
    if (_pos >= text.length) {
      return;
    }
    lines[pointer] = _index.positionOf(_pos).$1;
    final int c = text.codeUnitAt(_pos);
    if (c == 0x7b) {
      _object(pointer);
    } else if (c == 0x5b) {
      _array(pointer);
    } else if (c == 0x22) {
      _string();
    } else {
      _primitive();
    }
  }

  void _object(String pointer) {
    _pos++; // '{'
    _skipWhitespace();
    if (_peek() == 0x7d) {
      _pos++;
      return;
    }
    while (_pos < text.length) {
      _skipWhitespace();
      final String key = _string();
      _skipWhitespace();
      if (_peek() == 0x3a) {
        _pos++;
      }
      _value(joinPointer(pointer, key));
      _skipWhitespace();
      final int c = _peek();
      if (c == 0x2c) {
        _pos++;
        continue;
      }
      if (c == 0x7d) {
        _pos++;
      }
      return;
    }
  }

  void _array(String pointer) {
    _pos++; // '['
    _skipWhitespace();
    if (_peek() == 0x5d) {
      _pos++;
      return;
    }
    var i = 0;
    while (_pos < text.length) {
      _value(joinPointer(pointer, i));
      i++;
      _skipWhitespace();
      final int c = _peek();
      if (c == 0x2c) {
        _pos++;
        continue;
      }
      if (c == 0x5d) {
        _pos++;
      }
      return;
    }
  }

  String _string() {
    if (_peek() != 0x22) {
      _primitive();
      return '';
    }
    final int start = _pos;
    _pos++; // opening quote
    while (_pos < text.length) {
      final int c = text.codeUnitAt(_pos);
      if (c == 0x5c) {
        _pos += 2;
        continue;
      }
      _pos++;
      if (c == 0x22) {
        break;
      }
    }
    final String raw = text.substring(start, _pos);
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is String ? decoded : raw;
    } on FormatException {
      return raw;
    }
  }

  void _primitive() {
    while (_pos < text.length) {
      final int c = text.codeUnitAt(_pos);
      if (c == 0x2c || c == 0x7d || c == 0x5d || _isWhitespace(c)) {
        return;
      }
      _pos++;
    }
  }

  void _skipWhitespace() {
    while (_pos < text.length && _isWhitespace(text.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  int _peek() => _pos < text.length ? text.codeUnitAt(_pos) : -1;

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;
}
