import 'package:meta/meta.dart';

/// A strict [Semantic Versioning 2.0.0](https://semver.org) version.
///
/// The SDK ships its own parser rather than depending on `package:pub_semver`
/// so that the whole SDK stays dependency-free (only `meta` is allowed).
/// It is deliberately strict: every version that reaches the host has come
/// out of a manifest, and a manifest that says `1.2` or `v1.2.3` is a bug in
/// the plugin, not something to guess at.
///
/// Ordering follows the SemVer precedence rules exactly: numeric identifiers
/// compare numerically, alphanumeric identifiers compare in ASCII order,
/// numeric sorts below alphanumeric, a shorter pre-release sorts below a
/// longer one with the same prefix, and a version with a pre-release sorts
/// below the same version without one. Build metadata is ignored for
/// ordering, but it is part of value equality.
@immutable
final class Version implements Comparable<Version> {
  /// Creates a version from its parts.
  ///
  /// The caller is responsible for passing non-negative numbers and
  /// well-formed [preRelease] / [build] identifiers; use [parse] to get
  /// validation.
  const Version(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease,
    this.build,
  });

  /// The major version. Incremented for a breaking change.
  final int major;

  /// The minor version. Incremented for a backwards-compatible addition.
  final int minor;

  /// The patch version. Incremented for a backwards-compatible fix.
  final int patch;

  /// The dot-separated pre-release identifiers, without the leading `-`,
  /// or `null` for a stable release.
  final String? preRelease;

  /// The dot-separated build identifiers, without the leading `+`, or `null`.
  ///
  /// Build metadata never affects ordering.
  final String? build;

  static final RegExp _pattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)'
    r'(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?'
    r'(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$',
  );

  /// Parses [source] as a strict SemVer string.
  ///
  /// Throws [FormatException] if [source] is not strict SemVer — including
  /// leading zeroes (`01.0.0`), a missing patch (`1.2`), a `v` prefix, or an
  /// empty pre-release or build section. Callers parsing untrusted responses
  /// should catch that and rethrow it as a
  /// `SwayvePluginMalformedResponseException`; the models in this SDK do
  /// exactly that.
  static Version parse(String source) {
    final version = tryParse(source);
    if (version == null) {
      throw FormatException('Not a valid SemVer 2.0.0 version.', source);
    }
    return version;
  }

  /// Parses [source], returning `null` instead of throwing when it is not a
  /// valid version.
  static Version? tryParse(String source) {
    final match = _pattern.firstMatch(source);
    if (match == null) return null;
    return Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      preRelease: match.group(4),
      build: match.group(5),
    );
  }

  /// Whether this version carries pre-release identifiers.
  ///
  /// A pre-release version sorts below the same version without one, and
  /// signals that the API it describes is not yet stable.
  bool get isPreRelease => preRelease != null;

  /// The dot-separated pre-release identifiers, or an empty list.
  List<String> get preReleaseIdentifiers =>
      preRelease == null ? const <String>[] : preRelease!.split('.');

  /// Returns a copy of this version with the given parts replaced.
  ///
  /// Passing `null` keeps the existing value; use [Version.new] directly to
  /// clear [preRelease] or [build].
  Version copyWith({
    int? major,
    int? minor,
    int? patch,
    String? preRelease,
    String? build,
  }) =>
      Version(
        major ?? this.major,
        minor ?? this.minor,
        patch ?? this.patch,
        preRelease: preRelease ?? this.preRelease,
        build: build ?? this.build,
      );

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (preRelease == null && other.preRelease == null) return 0;
    if (preRelease == null) return 1;
    if (other.preRelease == null) return -1;
    return _comparePreRelease(
      preReleaseIdentifiers,
      other.preReleaseIdentifiers,
    );
  }

  static int _comparePreRelease(List<String> a, List<String> b) {
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      final left = a[i];
      final right = b[i];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        if (leftNumber != rightNumber) return leftNumber.compareTo(rightNumber);
        continue;
      }
      if (leftNumber != null) return -1;
      if (rightNumber != null) return 1;
      final byText = left.compareTo(right);
      if (byText != 0) return byText;
    }
    return a.length.compareTo(b.length);
  }

  /// Whether this version sorts strictly below [other].
  bool operator <(Version other) => compareTo(other) < 0;

  /// Whether this version sorts below or equal to [other].
  bool operator <=(Version other) => compareTo(other) <= 0;

  /// Whether this version sorts strictly above [other].
  bool operator >(Version other) => compareTo(other) > 0;

  /// Whether this version sorts above or equal to [other].
  bool operator >=(Version other) => compareTo(other) >= 0;

  /// The canonical SemVer string. Round-trips through [parse].
  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (preRelease != null) buffer.write('-$preRelease');
    if (build != null) buffer.write('+$build');
    return buffer.toString();
  }

  /// The wire form of a version: its canonical string.
  ///
  /// Unlike the models in this SDK, a version serializes to a string rather
  /// than an object, because that is how it appears in `plugin.json`.
  String toJson() => toString();

  /// Parses the wire form produced by [toJson].
  static Version fromJson(String json) => parse(json);

  @override
  bool operator ==(Object other) =>
      other is Version &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      preRelease == other.preRelease &&
      build == other.build;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease, build);
}

/// An alias for [Version], for code that imports the SDK alongside a host
/// type of the same name.
///
/// The host's own classes are not `Swayve`-prefixed, so a plugin importing
/// both may need to disambiguate; this alias means it never has to rename an
/// import to do so.
typedef SwayveVersion = Version;
