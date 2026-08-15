import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

/// Principle 6: streamable, downloadable and on-device are three independent
/// facts. These are regression guards — if anyone ever "helpfully" derives
/// one flag from another, every test in this file fails.
void main() {
  test('every combination of the three flags is representable', () {
    final seen = <SwayveAvailability>{};
    for (final streamable in [false, true]) {
      for (final downloadable in [false, true]) {
        for (final onDevice in [false, true]) {
          final value = SwayveAvailability(
            streamable: streamable,
            downloadable: downloadable,
            onDevice: onDevice,
          );
          expect(value.streamable, streamable);
          expect(value.downloadable, downloadable);
          expect(value.onDevice, onDevice);
          seen.add(value);
        }
      }
    }
    expect(seen.length, 8, reason: 'all 8 combinations must be distinct');
  });

  test('streamable does not imply downloadable', () {
    const value = SwayveAvailability(streamable: true);
    expect(value.downloadable, isFalse);
    expect(value.onDevice, isFalse);
  });

  test('downloadable does not imply streamable', () {
    const value = SwayveAvailability(downloadable: true);
    expect(value.streamable, isFalse);
  });

  test('onDevice does not imply streamable or downloadable', () {
    const value = SwayveAvailability(onDevice: true);
    expect(value.streamable, isFalse);
    expect(value.downloadable, isFalse);
  });

  test('copyWith changes one flag without disturbing the others', () {
    const start = SwayveAvailability(streamable: true, onDevice: true);
    final changed = start.copyWith(downloadable: true);
    expect(changed.streamable, isTrue);
    expect(changed.onDevice, isTrue);
    expect(changed.downloadable, isTrue);
    expect(start.downloadable, isFalse, reason: 'the original is immutable');
  });

  test('the wire form always writes all three flags', () {
    final json = SwayveAvailability.streamOnly.toJson();
    expect(json.keys.toSet(), {'streamable', 'downloadable', 'onDevice'});
    expect(json['streamable'], isTrue);
    expect(json['downloadable'], isFalse);
    expect(json['onDevice'], isFalse);
  });

  test('a flag missing from the wire form reads as denied', () {
    final parsed = SwayveAvailability.fromJson({'streamable': true});
    expect(parsed, SwayveAvailability.streamOnly);
  });

  test('the named constants mean what they say', () {
    expect(SwayveAvailability.streamOnly.streamable, isTrue);
    expect(SwayveAvailability.streamOnly.downloadable, isFalse);
    expect(SwayveAvailability.streamOnly.onDevice, isFalse);
    expect(SwayveAvailability.none.isPlayable, isFalse);
    expect(SwayveAvailability.streamOnly.isPlayable, isTrue);
    expect(const SwayveAvailability(onDevice: true).isPlayable, isTrue);
  });

  test('a track keeps the availability its provider gave it', () {
    const id = SwayveMediaId('a.b.c', 'x');
    const track = SwayveTrack(
      id: id,
      title: 'Licensed for offline only',
      availability: SwayveAvailability(downloadable: true),
    );
    final parsed = SwayveTrack.fromJson(track.toJson());
    expect(parsed.availability.downloadable, isTrue);
    expect(parsed.availability.streamable, isFalse);
    expect(parsed.availability.onDevice, isFalse);
  });
}
