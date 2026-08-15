import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

void main() {
  group('parsing', () {
    test('accepts the shapes SemVer 2.0.0 defines', () {
      for (final String version in <String>[
        '0.0.4',
        '1.2.3',
        '10.20.30',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-0.3.7',
        '1.0.0-x.7.z.92',
        '1.0.0+20130313144700',
        '1.0.0-beta+exp.sha.5114f85',
      ]) {
        expect(SemVer.tryParse(version), isNotNull, reason: version);
      }
    });

    test('rejects the shapes it does not', () {
      for (final String version in <String>[
        '1',
        '1.2',
        '1.2.3.4',
        '01.2.3',
        '1.2.3-',
        '1.2.3-01',
        'v1.2.3',
        '1.2.3 ',
        '',
      ]) {
        expect(SemVer.tryParse(version), isNull, reason: "'$version'");
      }
    });

    test('keeps the parts apart', () {
      final SemVer version = SemVer.tryParse('1.2.3-beta.1+build.7')!;
      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.preRelease, 'beta.1');
      expect(version.build, 'build.7');
      expect(version.isPreRelease, isTrue);
      expect(version.toString(), '1.2.3-beta.1+build.7');
    });
  });

  group('ordering', () {
    SemVer v(String s) => SemVer.tryParse(s)!;

    test('a release outranks its own pre-releases', () {
      expect(v('1.0.0').compareTo(v('1.0.0-rc.1')), greaterThan(0));
      expect(v('1.0.0-rc.1').compareTo(v('1.0.0')), lessThan(0));
    });

    test('follows the precedence example from the spec', () {
      final List<String> ascending = <String>[
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
      ];
      for (var i = 0; i + 1 < ascending.length; i++) {
        expect(
          v(ascending[i]).compareTo(v(ascending[i + 1])),
          lessThan(0),
          reason: '${ascending[i]} should sort below ${ascending[i + 1]}',
        );
      }
    });

    test('build metadata does not affect precedence', () {
      expect(v('1.0.0+a').compareTo(v('1.0.0+b')), 0);
    });
  });

  test('0.x is the unstable band', () {
    expect(SemVer.tryParse('0.9.9')!.isUnstable, isTrue);
    expect(SemVer.tryParse('1.0.0')!.isUnstable, isFalse);
  });
}
