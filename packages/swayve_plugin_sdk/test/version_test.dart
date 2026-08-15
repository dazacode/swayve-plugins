import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('Version.parse', () {
    test('parses a plain release', () {
      final version = Version.parse('1.2.3');
      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.preRelease, isNull);
      expect(version.build, isNull);
      expect(version.isPreRelease, isFalse);
    });

    test('parses a pre-release', () {
      final version = Version.parse('1.0.0-alpha.1');
      expect(version.preRelease, 'alpha.1');
      expect(version.isPreRelease, isTrue);
      expect(version.preReleaseIdentifiers, ['alpha', '1']);
    });

    test('parses build metadata', () {
      final version = Version.parse('1.0.0+20130313144700');
      expect(version.build, '20130313144700');
      expect(version.isPreRelease, isFalse);
    });

    test('parses both a pre-release and build metadata', () {
      final version = Version.parse('1.0.0-beta.2+exp.sha.5114f85');
      expect(version.preRelease, 'beta.2');
      expect(version.build, 'exp.sha.5114f85');
    });

    test('parses zeroes', () {
      expect(Version.parse('0.0.0').toString(), '0.0.0');
    });

    test('round-trips through toString for every accepted form', () {
      const inputs = <String>[
        '0.0.4',
        '1.2.3',
        '10.20.30',
        '1.1.2-prerelease+meta',
        '1.1.2+meta',
        '1.0.0-alpha',
        '1.0.0-alpha.beta',
        '1.0.0-alpha0.valid',
        '1.0.0-rc.1+build.1',
        '2.0.0-rc.1+build.123',
        '1.2.3-SNAPSHOT-123',
        '1.0.0-0A.is.legal',
      ];
      for (final input in inputs) {
        expect(Version.parse(input).toString(), input, reason: input);
      }
    });

    test('round-trips through toJson/fromJson', () {
      final version = Version.parse('3.4.5-rc.2+sha.abc');
      expect(Version.fromJson(version.toJson()), version);
    });
  });

  group('Version.parse rejects junk', () {
    const junk = <String>[
      '',
      '1',
      '1.2',
      '1.2.3.4',
      'v1.2.3',
      '01.2.3',
      '1.02.3',
      '1.2.03',
      '1.2.3-',
      '1.2.3+',
      '1.2.3-+meta',
      'alpha',
      '1.2.3 ',
      ' 1.2.3',
      '1.2.-3',
      '-1.2.3',
      '1.2.3-alpha..1',
      '1.2.3-01',
      'not.a.version',
      '1.2.3+meta+more',
    ];

    for (final input in junk) {
      test('"$input"', () {
        expect(() => Version.parse(input), throwsFormatException);
        expect(Version.tryParse(input), isNull);
      });
    }
  });

  group('ordering', () {
    test('follows SemVer precedence', () {
      final ordered = <Version>[
        Version.parse('1.0.0-alpha'),
        Version.parse('1.0.0-alpha.1'),
        Version.parse('1.0.0-alpha.beta'),
        Version.parse('1.0.0-beta'),
        Version.parse('1.0.0-beta.2'),
        Version.parse('1.0.0-beta.11'),
        Version.parse('1.0.0-rc.1'),
        Version.parse('1.0.0'),
        Version.parse('1.0.1'),
        Version.parse('1.1.0'),
        Version.parse('2.0.0'),
      ];
      final shuffled = List<Version>.of(ordered.reversed)..sort();
      expect(shuffled, ordered);
    });

    test('numeric pre-release identifiers compare numerically', () {
      expect(Version.parse('1.0.0-2') < Version.parse('1.0.0-11'), isTrue);
    });

    test('numeric identifiers sort below alphanumeric ones', () {
      expect(Version.parse('1.0.0-1') < Version.parse('1.0.0-alpha'), isTrue);
    });

    test('a shorter pre-release sorts below a longer prefix match', () {
      expect(
        Version.parse('1.0.0-alpha') < Version.parse('1.0.0-alpha.1'),
        isTrue,
      );
    });

    test('a pre-release sorts below its release', () {
      expect(Version.parse('1.0.0-rc.1') < Version.parse('1.0.0'), isTrue);
      expect(Version.parse('1.0.0') > Version.parse('1.0.0-rc.1'), isTrue);
    });

    test('build metadata is ignored for ordering', () {
      expect(
        Version.parse('1.0.0+a').compareTo(Version.parse('1.0.0+b')),
        0,
      );
      expect(Version.parse('1.0.0+a') >= Version.parse('1.0.0+b'), isTrue);
      expect(Version.parse('1.0.0+a') <= Version.parse('1.0.0+b'), isTrue);
    });

    test('build metadata is part of value equality', () {
      expect(Version.parse('1.0.0+a'), isNot(Version.parse('1.0.0+b')));
      expect(Version.parse('1.0.0+a'), Version.parse('1.0.0+a'));
      expect(
        Version.parse('1.0.0+a').hashCode,
        Version.parse('1.0.0+a').hashCode,
      );
    });
  });

  test('copyWith replaces only what it is given', () {
    final version = Version.parse('1.2.3-rc.1');
    expect(version.copyWith(patch: 9).toString(), '1.2.9-rc.1');
    expect(version.copyWith().toString(), '1.2.3-rc.1');
  });

  test('SwayveVersion is an alias for Version', () {
    const SwayveVersion aliased = Version(1, 0, 0);
    expect(aliased, const Version(1, 0, 0));
  });
}
