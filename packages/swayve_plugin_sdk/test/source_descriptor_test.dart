import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('SwayveSourceDescriptor', () {
    const descriptor = SwayveSourceDescriptor(
      sourceId: 'demo_source',
      displayName: 'Demo Source',
      iconName: 'demo_source',
      contentTypes: {SwayveContentType.songs, SwayveContentType.albums},
      capabilities: {SwayveCapability.search, SwayveCapability.catalog},
    );

    test('survives a wire round trip', () {
      expect(
        SwayveSourceDescriptor.fromJson(descriptor.toJson()),
        descriptor,
      );
    });

    test(
        'serializes its sets in declaration order, whatever order they were '
        'built in', () {
      final shuffled = descriptor.copyWith(
        contentTypes: {SwayveContentType.albums, SwayveContentType.songs},
      );
      expect(shuffled.toJson(), descriptor.toJson());
      expect(
        descriptor.toJson()['contentTypes'],
        <String>['songs', 'albums'],
      );
    });

    test('reads searchability off the capability list rather than a flag', () {
      expect(descriptor.canSearch, isTrue);
      expect(
        descriptor.copyWith(capabilities: {SwayveCapability.catalog}).canSearch,
        isFalse,
      );
    });

    test('answers only for a content type it declared, while it is ready', () {
      expect(descriptor.answers(SwayveContentType.songs), isTrue);
      expect(descriptor.answers(SwayveContentType.videos), isFalse);
      expect(
        descriptor
            .copyWith(availability: SwayveSourceAvailability.signedOut)
            .answers(SwayveContentType.songs),
        isFalse,
      );
    });

    test(
        'defaults to ready, because a manifest states a default rather than '
        'an observation', () {
      expect(descriptor.availability, SwayveSourceAvailability.ready);
      expect(descriptor.availability.canAnswer, isTrue);
    });
  });

  group('SwayveSourceDescriptor.fromManifest', () {
    test('reads a whole source block', () {
      final read = SwayveSourceDescriptor.fromManifest(
        <String, Object?>{
          'sourceId': 'demo_source',
          'displayName': 'Demo Source',
          'iconName': 'demo_source',
          'contentTypes': <String>['songs', 'videos'],
          'availability': 'signed_out',
        },
        capabilities: <String>['search', 'streaming'],
      );
      expect(read, isNotNull);
      expect(read!.sourceId, 'demo_source');
      expect(read.displayName, 'Demo Source');
      expect(read.iconName, 'demo_source');
      expect(
        read.contentTypes,
        <SwayveContentType>{SwayveContentType.songs, SwayveContentType.videos},
      );
      expect(read.availability, SwayveSourceAvailability.signedOut);
      expect(read.canSearch, isTrue);
    });

    test('drops an unrecognised content type rather than losing the source',
        () {
      final read = SwayveSourceDescriptor.fromManifest(<String, Object?>{
        'sourceId': 'demo_source',
        'contentTypes': <Object?>['songs', 'podcasts', 42],
      });
      expect(read!.contentTypes, <SwayveContentType>{SwayveContentType.songs});
    });

    test('drops an unrecognised capability the same way', () {
      final read = SwayveSourceDescriptor.fromManifest(
        <String, Object?>{'sourceId': 'demo_source'},
        capabilities: <String>['search', 'telepathy'],
      );
      expect(read!.capabilities, <SwayveCapability>{SwayveCapability.search});
    });

    test('falls back to the id when no display name was given', () {
      final read = SwayveSourceDescriptor.fromManifest(
        <String, Object?>{'sourceId': 'demo_source'},
      );
      expect(read!.displayName, 'demo_source');
      expect(read.iconName, isNull);
    });

    test('answers null for anything that is not a usable source block', () {
      expect(SwayveSourceDescriptor.fromManifest(null), isNull);
      expect(SwayveSourceDescriptor.fromManifest('demo_source'), isNull);
      expect(SwayveSourceDescriptor.fromManifest(<String, Object?>{}), isNull);
      expect(
        SwayveSourceDescriptor.fromManifest(
          <String, Object?>{'sourceId': '   '},
        ),
        isNull,
      );
    });

    test('reads an unknown or absent availability as ready', () {
      // A manifest cannot know what its service will be doing months later, so
      // an availability it cannot spell is not worth refusing the source over.
      for (final Object? raw in <Object?>[null, 'melting', 7]) {
        final read = SwayveSourceDescriptor.fromManifest(<String, Object?>{
          'sourceId': 'demo_source',
          'availability': raw,
        });
        expect(read!.availability, SwayveSourceAvailability.ready);
      }
    });
  });

  group('SwayveContentType and SwayveSourceAvailability', () {
    test('every content type round trips through its wire name', () {
      for (final type in SwayveContentType.values) {
        expect(SwayveContentType.fromWire(type.wireName), type);
      }
      expect(SwayveContentType.fromWire('podcasts'), isNull);
    });

    test('every availability round trips through its wire name', () {
      for (final value in SwayveSourceAvailability.values) {
        expect(SwayveSourceAvailability.fromWire(value.wireName), value);
      }
      expect(SwayveSourceAvailability.fromWire('melting'), isNull);
    });

    test('only ready can answer', () {
      for (final value in SwayveSourceAvailability.values) {
        expect(
          value.canAnswer,
          value == SwayveSourceAvailability.ready,
          reason: value.wireName,
        );
      }
    });
  });
}
