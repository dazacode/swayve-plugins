import 'package:path/path.dart' as p;

/// The ways a relative path can be unsafe.
enum PathProblem {
  /// Nothing there at all.
  empty,

  /// Rooted at `/`, so it would escape wherever it is unpacked.
  absolute,

  /// Contains a `..` segment.
  parentTraversal,

  /// Contains a backslash, which some unpackers treat as a separator.
  backslash,

  /// Carries a Windows drive letter or a UNC prefix.
  driveLetter,

  /// Contains a NUL byte or another C0 control character.
  controlCharacter,
}

/// Everything wrong with [path], in a fixed order so diagnostics are stable.
///
/// This is the shared rule behind manifest rule 10 and the bundle extraction
/// checks: a path we accept must be relative, must stay put, and must not lean
/// on any platform's separator quirks.
List<PathProblem> pathProblems(String path) {
  final List<PathProblem> problems = <PathProblem>[];
  if (path.isEmpty) {
    return <PathProblem>[PathProblem.empty];
  }
  for (var i = 0; i < path.length; i++) {
    final int c = path.codeUnitAt(i);
    if (c < 0x20 || c == 0x7f) {
      problems.add(PathProblem.controlCharacter);
      break;
    }
  }
  if (path.contains('\\')) {
    problems.add(PathProblem.backslash);
  }
  if (_drivePattern.hasMatch(path) || path.startsWith('//')) {
    problems.add(PathProblem.driveLetter);
  }
  if (path.startsWith('/')) {
    problems.add(PathProblem.absolute);
  }
  final List<String> segments = path.split(RegExp(r'[/\\]'));
  if (segments.contains('..')) {
    problems.add(PathProblem.parentTraversal);
  }
  return problems;
}

/// A short reason phrase for [problem], for use inside a diagnostic message.
String describePathProblem(PathProblem problem) => switch (problem) {
      PathProblem.empty => 'is empty',
      PathProblem.absolute => 'is absolute',
      PathProblem.parentTraversal => "contains a '..' segment",
      PathProblem.backslash => 'contains a backslash',
      PathProblem.driveLetter => 'carries a drive letter or UNC prefix',
      PathProblem.controlCharacter => 'contains a control character',
    };

/// Whether unpacking [entryPath] under [root] lands inside [root].
///
/// Checked after normalisation, which is the only order that matters:
/// `a/../../b` looks harmless segment by segment and is not.
bool staysInsideRoot(String root, String entryPath) {
  final String normalizedRoot = p.posix.normalize(_toPosix(root));
  final String entry = _toPosix(entryPath);
  if (entry.isEmpty || p.posix.isAbsolute(entry)) {
    return false;
  }
  final String resolved =
      p.posix.normalize(p.posix.join(normalizedRoot, entry));
  return p.posix.isWithin(normalizedRoot, resolved);
}

/// Normalises [entryPath] to the form used as an archive member name.
///
/// Strips a single leading `./` and collapses redundant separators. It does not
/// resolve `..`; anything containing one is rejected outright before this runs.
String canonicalArchivePath(String entryPath) {
  final String posixPath = _toPosix(entryPath);
  final List<String> parts = posixPath
      .split('/')
      .where((String s) => s.isNotEmpty && s != '.')
      .toList(growable: false);
  return parts.join('/');
}

String _toPosix(String value) => value.replaceAll('\\', '/');

final RegExp _drivePattern = RegExp(r'^[A-Za-z]:');
