import 'package:meta/meta.dart';

import '../internal/json.dart';

/// Three independent facts about what can be done with an item.
///
/// Principle 6: **streamable != downloadable != on-device**. None of these
/// may be derived from another, in either direction:
///
/// * [streamable] — the provider can hand the host a playable source right
///   now, over the network.
/// * [downloadable] — the provider permits keeping a copy for offline use.
///   A track can be streamable and not downloadable (the common licensing
///   case) or downloadable and not currently streamable (the service is down
///   but a previously granted download is still permitted).
/// * [onDevice] — a copy already exists locally. This says nothing about
///   whether the user is still permitted to play it; permission lives in the
///   other two flags and, on the host side, in its own grant model.
///
/// The host reads all three. A provider that collapses them — for example by
/// setting [downloadable] whenever [streamable] is true — is lying to the
/// host about the rights it holds.
@immutable
final class SwayveAvailability {
  /// Creates an availability record. Every flag defaults to `false`: a
  /// provider must opt in to each fact it can actually vouch for.
  const SwayveAvailability({
    this.streamable = false,
    this.downloadable = false,
    this.onDevice = false,
  });

  /// Whether the provider can resolve this item to a playable source now.
  final bool streamable;

  /// Whether the provider permits storing a copy for offline playback.
  final bool downloadable;

  /// Whether a copy already exists on this device.
  final bool onDevice;

  /// Playable over the network, not downloadable, not on device.
  ///
  /// The default posture for a streaming service that grants no offline
  /// rights.
  static const SwayveAvailability streamOnly =
      SwayveAvailability(streamable: true);

  /// Nothing is possible with this item.
  ///
  /// Use it for an item that is listed but cannot currently be played, so
  /// the host can show it greyed out rather than dropping it.
  static const SwayveAvailability none = SwayveAvailability();

  /// Whether the item can be played at all right now, by any route.
  bool get isPlayable => streamable || onDevice;

  /// Returns a copy with the given flags replaced.
  SwayveAvailability copyWith({
    bool? streamable,
    bool? downloadable,
    bool? onDevice,
  }) =>
      SwayveAvailability(
        streamable: streamable ?? this.streamable,
        downloadable: downloadable ?? this.downloadable,
        onDevice: onDevice ?? this.onDevice,
      );

  /// The wire form. All three flags are always written, because an omitted
  /// flag would be indistinguishable from a denied one.
  Map<String, Object?> toJson() => {
        'streamable': streamable,
        'downloadable': downloadable,
        'onDevice': onDevice,
      };

  /// Parses the wire form produced by [toJson]. Missing flags read as
  /// `false`.
  static SwayveAvailability fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveAvailability', json);
    return SwayveAvailability(
      streamable: reader.boolean('streamable'),
      downloadable: reader.boolean('downloadable'),
      onDevice: reader.boolean('onDevice'),
    );
  }

  @override
  String toString() => 'SwayveAvailability(streamable: $streamable, '
      'downloadable: $downloadable, onDevice: $onDevice)';

  @override
  bool operator ==(Object other) =>
      other is SwayveAvailability &&
      streamable == other.streamable &&
      downloadable == other.downloadable &&
      onDevice == other.onDevice;

  @override
  int get hashCode => Object.hash(streamable, downloadable, onDevice);
}
