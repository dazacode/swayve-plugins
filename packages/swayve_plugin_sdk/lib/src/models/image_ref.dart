import 'package:meta/meta.dart';

import '../internal/json.dart';

/// A pointer to an image the host may fetch and render.
///
/// Principle 5: plugins supply data, the host renders UI. A plugin never
/// hands over decoded bytes or a widget — only a location and, where it knows
/// them, enough hints for the host to lay out and placeholder the image
/// without a round trip.
@immutable
final class SwayveImageRef {
  /// Creates an image reference.
  const SwayveImageRef({
    required this.uri,
    this.width,
    this.height,
    this.blurHash,
  });

  /// Where the image lives.
  ///
  /// Usually `https:`. If the plugin has the `network` permission the host
  /// fetches it through the same restricted client the plugin would use.
  final Uri uri;

  /// The image's width in pixels, when the provider knows it.
  final int? width;

  /// The image's height in pixels, when the provider knows it.
  final int? height;

  /// A BlurHash placeholder the host may render while the image loads.
  final String? blurHash;

  /// The aspect ratio, when both dimensions are known.
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || h == 0) return null;
    return w / h;
  }

  /// Returns a copy with the given fields replaced.
  SwayveImageRef copyWith({
    Uri? uri,
    int? width,
    int? height,
    String? blurHash,
  }) =>
      SwayveImageRef(
        uri: uri ?? this.uri,
        width: width ?? this.width,
        height: height ?? this.height,
        blurHash: blurHash ?? this.blurHash,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'uri': uri.toString(),
        'width': width,
        'height': height,
        'blurHash': blurHash,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveImageRef fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveImageRef', json);
    return SwayveImageRef(
      uri: reader.uri('uri'),
      width: reader.integerOrNull('width'),
      height: reader.integerOrNull('height'),
      blurHash: reader.stringOrNull('blurHash'),
    );
  }

  @override
  String toString() => 'SwayveImageRef($uri)';

  @override
  bool operator ==(Object other) =>
      other is SwayveImageRef &&
      uri == other.uri &&
      width == other.width &&
      height == other.height &&
      blurHash == other.blurHash;

  @override
  int get hashCode => Object.hash(uri, width, height, blurHash);
}
