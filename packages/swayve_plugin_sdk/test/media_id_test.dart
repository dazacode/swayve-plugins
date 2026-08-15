import 'dart:convert';

import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('SwayveMediaId.uri', () {
    test('uses the swayve scheme and the owning plugin id', () {
      const id = SwayveMediaId('app.swayve.plugins.example', 'abc123');
      expect(id.uri, 'swayve://app.swayve.plugins.example/abc123');
    });

    test('percent-encodes characters that would break the URI', () {
      const id = SwayveMediaId('p.q.r', 'a/b c?d#e&f=g');
      expect(id.uri.contains('/b'), isFalse);
      expect(id.uri, 'swayve://p.q.r/a%2Fb%20c%3Fd%23e%26f%3Dg');
    });
  });

  group('SwayveMediaId round trip', () {
    final awkward = <String>[
      'plain',
      'with/slashes/everywhere',
      'with spaces',
      'question?mark',
      'hash#fragment',
      'percent%20already',
      'plus+sign',
      'ampersand&equals=',
      'colon:and:more',
      'unicode — ünïcødé 日本語 🎵',
      'quotes "double" and \'single\'',
      'trailing/',
      '/leading',
      '',
      'a' * 512,
      r'back\slash',
      'newline\nand\ttab',
    ];

    for (final value in awkward) {
      test('round-trips ${jsonEncode(value)}', () {
        final id = SwayveMediaId('app.swayve.plugins.example', value);
        final parsed = SwayveMediaId.parse(id.uri);
        expect(parsed.value, value);
        expect(parsed.pluginId, 'app.swayve.plugins.example');
        expect(parsed, id);
        expect(parsed.hashCode, id.hashCode);
      });
    }

    test('round-trips through toJson/fromJson', () {
      const id = SwayveMediaId('a.b.c', 'weird / value ?');
      expect(SwayveMediaId.fromJson(id.toJson()), id);
    });

    test('round-trips through a real JSON encode/decode', () {
      const id = SwayveMediaId('a.b.c', 'unicode ünïcødé / 🎵');
      final decoded = jsonDecode(jsonEncode(id.toJson()));
      expect(
        SwayveMediaId.fromJson(decoded as Map<String, Object?>),
        id,
      );
    });

    test('accepts the compact uri form in fromJson', () {
      const id = SwayveMediaId('a.b.c', 'x/y z');
      expect(SwayveMediaId.fromJson({'uri': id.uri}), id);
    });
  });

  group('SwayveMediaId.parse rejects', () {
    const junk = <String>[
      'https://example.com/thing',
      'swayve:/missing-slash',
      'swayve://',
      'swayve://no-value-separator',
      'swayve:///empty-plugin',
      '',
      'not a uri at all',
      'swayve://plugin/%zz',
    ];

    for (final input in junk) {
      test(jsonEncode(input), () {
        expect(
          () => SwayveMediaId.parse(input),
          throwsA(isA<SwayvePluginMalformedResponseException>()),
        );
        expect(SwayveMediaId.tryParse(input), isNull);
      });
    }
  });

  test('toString is the uri', () {
    const id = SwayveMediaId('a.b.c', 'v 1');
    expect(id.toString(), id.uri);
  });

  test('ids from different plugins are never equal', () {
    expect(
      const SwayveMediaId('a.b.c', 'x'),
      isNot(const SwayveMediaId('a.b.d', 'x')),
    );
  });
}
