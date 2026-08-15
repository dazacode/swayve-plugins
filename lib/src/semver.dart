/// Strict SemVer 2.0.0, parsed without a package dependency.
///
/// The tools only need to answer three questions: is this a valid version, is
/// it below 1.0.0, and which of two versions is newer. That is small enough to
/// own outright, and owning it keeps the schema's `pattern` and the validator's
/// behaviour provably the same thing.
final class SemVer implements Comparable<SemVer> {
  /// Creates a version from its parts.
  const SemVer(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease,
    this.build,
  });

  /// The regex published at semver.org. Byte-identical to the schema's
  /// `$defs/semver` pattern; `test/schema_sync_test.dart` proves it.
  static final RegExp pattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)'
    r'(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?'
    r'(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$',
  );

  /// Major version.
  final int major;

  /// Minor version.
  final int minor;

  /// Patch version.
  final int patch;

  /// Pre-release identifiers, without the leading `-`.
  final String? preRelease;

  /// Build metadata, without the leading `+`. Ignored when comparing.
  final String? build;

  /// Parses [input], or returns `null` if it is not strict SemVer.
  static SemVer? tryParse(String input) {
    final RegExpMatch? m = pattern.firstMatch(input);
    if (m == null) {
      return null;
    }
    return SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      preRelease: m.group(4),
      build: m.group(5),
    );
  }

  /// Whether this version is below `1.0.0`, i.e. the surface is still unstable.
  bool get isUnstable => major == 0;

  /// Whether this version carries pre-release identifiers.
  bool get isPreRelease => preRelease != null;

  @override
  int compareTo(SemVer other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }
    final String? a = preRelease;
    final String? b = other.preRelease;
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1; // a release outranks a pre-release
    }
    if (b == null) {
      return -1;
    }
    return _comparePreRelease(a, b);
  }

  static int _comparePreRelease(String a, String b) {
    final List<String> left = a.split('.');
    final List<String> right = b.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      final int? ln = int.tryParse(left[i]);
      final int? rn = int.tryParse(right[i]);
      final int c;
      if (ln != null && rn != null) {
        c = ln.compareTo(rn);
      } else if (ln != null) {
        c = -1; // numeric identifiers rank below alphanumeric ones
      } else if (rn != null) {
        c = 1;
      } else {
        c = left[i].compareTo(right[i]);
      }
      if (c != 0) {
        return c;
      }
    }
    return left.length.compareTo(right.length);
  }

  @override
  bool operator ==(Object other) =>
      other is SemVer && compareTo(other) == 0 && build == other.build;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease, build);

  @override
  String toString() {
    final StringBuffer b = StringBuffer('$major.$minor.$patch');
    if (preRelease != null) {
      b.write('-$preRelease');
    }
    if (build != null) {
      b.write('+$build');
    }
    return b.toString();
  }
}
