import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

/// The one parser in this SDK that is deliberately lenient.
///
/// Everything else here crossed a boundary the SDK controls. This crossed a
/// JavaScript channel out of a page written by a plugin author, where a number
/// may arrive as a string and a missing field is a script that has not finished
/// loading. A throw would take down the player it was describing.
void main() {
  group('reading what a page reports', () {
    test('a full state event reads as one', () {
      final SwayveEmbedEvent event = SwayveEmbedEvent.fromJson(
        <String, Object?>{
          'type': 'state',
          'playing': true,
          'position': 12.5,
          'duration': 210.0,
        },
      );

      expect(event.type, SwayveEmbedEventType.state);
      expect(event.playing, isTrue);
      expect(event.position, const Duration(milliseconds: 12500));
      expect(event.duration, const Duration(seconds: 210));
    });

    test('seconds may arrive as a string', () {
      final SwayveEmbedEvent event = SwayveEmbedEvent.fromJson(
        <String, Object?>{'type': 'state', 'position': '12.5'},
      );

      expect(
        event.position,
        const Duration(milliseconds: 12500),
        reason: 'The value may have come from a player API that reports a '
            'string, and refusing it would be pedantry at the cost of a '
            'working scrubber.',
      );
    });

    test('an empty message is a state event at zero, not a throw', () {
      final SwayveEmbedEvent event =
          SwayveEmbedEvent.fromJson(const <String, Object?>{});

      expect(event.type, SwayveEmbedEventType.state);
      expect(event.playing, isFalse);
      expect(event.position, Duration.zero);
      expect(event.duration, isNull);
    });

    test('an unknown type reads as a state change', () {
      expect(
        SwayveEmbedEvent.fromJson(
          <String, Object?>{'type': 'something-new'},
        ).type,
        SwayveEmbedEventType.state,
        reason: 'A page from a newer plugin must not be able to break an '
            'older host.',
      );
    });

    test('a live stream reports no duration rather than an absurd one', () {
      for (final Object? absurd in <Object?>[
        double.infinity,
        double.nan,
        -1,
        'not a number',
        null,
      ]) {
        expect(
          SwayveEmbedEvent.fromJson(
            <String, Object?>{'type': 'state', 'duration': absurd},
          ).duration,
          isNull,
          reason: '$absurd must not become a scrubber that is permanently at '
              'the end.',
        );
      }
    });

    test('an error carries the page\'s own sentence', () {
      final SwayveEmbedEvent event = SwayveEmbedEvent.fromJson(
        <String, Object?>{'type': 'error', 'message': 'Blocked here.'},
      );

      expect(event.type, SwayveEmbedEventType.error);
      expect(event.message, 'Blocked here.');
    });

    test('it round-trips through its own wire form', () {
      const SwayveEmbedEvent event = SwayveEmbedEvent(
        type: SwayveEmbedEventType.ended,
        position: Duration(seconds: 42),
        duration: Duration(seconds: 42),
      );

      expect(SwayveEmbedEvent.fromJson(event.toJson()), event);
    });
  });

  group('what makes an embed drivable', () {
    final Uri page = Uri.parse('https://example.test/embed/1');

    test('a document and controls together', () {
      expect(
        SwayveWebEmbed(
          kind: SwayveWebEmbedKind.inAppWebView,
          uri: page,
          controls: const <SwayveEmbedControl>{SwayveEmbedControl.play},
          document: '<!doctype html>',
        ).isDrivable,
        isTrue,
      );
    });

    test('controls with no document is a promise with no way to keep it', () {
      expect(
        SwayveWebEmbed(
          kind: SwayveWebEmbedKind.inAppWebView,
          uri: page,
          controls: const <SwayveEmbedControl>{SwayveEmbedControl.play},
        ).isDrivable,
        isFalse,
      );
    });

    test('a document with no controls declares nothing drivable', () {
      expect(
        SwayveWebEmbed(
          kind: SwayveWebEmbedKind.inAppWebView,
          uri: page,
          document: '<!doctype html>',
        ).isDrivable,
        isFalse,
      );
    });

    test('the document survives the wire', () {
      final SwayveWebEmbed embed = SwayveWebEmbed(
        kind: SwayveWebEmbedKind.inAppWebView,
        uri: page,
        controls: const <SwayveEmbedControl>{SwayveEmbedControl.seek},
        document: '<!doctype html><p>hello</p>',
      );

      expect(SwayveWebEmbed.fromJson(embed.toJson()), embed);
    });
  });
}
