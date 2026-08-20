import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

void main() {
  const names = SwayveAlternateNames(
    originalTitle: 'おやすみがこわい',
    romanizedTitle: 'Oyasumi ga Kowai',
    translatedTitle: "I'm Afraid to Sleep",
    originalArtist: 'ヨルシカ',
    romanizedArtist: 'Yorushika',
    originalAlbum: '負け犬にアンコールはいらない',
    romanizedAlbum: 'Makeinu ni Encore wa Iranai',
    aliases: <String>['Oyasumi ga Kowai (Remastered)'],
  );

  group('SwayveAlternateNames', () {
    test('survives a wire round trip', () {
      expect(SwayveAlternateNames.fromJson(names.toJson()), names);
    });

    test('a set that says nothing writes nothing', () {
      expect(SwayveAlternateNames.none.toJson(), isEmpty);
      expect(SwayveAlternateNames.none.isEmpty, isTrue);
      expect(names.isNotEmpty, isTrue);
    });

    test('a partly filled set carries only what it knows', () {
      const one = SwayveAlternateNames(romanizedTitle: 'Oyasumi ga Kowai');
      expect(one.toJson(), <String, Object?>{
        'romanizedTitle': 'Oyasumi ga Kowai',
      });
      expect(SwayveAlternateNames.fromJson(one.toJson()), one);
    });

    test('allNames drops the blanks and keeps the order', () {
      expect(
        const SwayveAlternateNames(
          romanizedTitle: 'Yoru ni Kakeru',
          translatedTitle: '   ',
          aliases: <String>['Racing into the Night'],
        ).allNames,
        <String>['Yoru ni Kakeru', 'Racing into the Night'],
      );
      expect(SwayveAlternateNames.none.allNames, isEmpty);
    });
  });

  group('SwayveTrack.alternateNames', () {
    const id = SwayveMediaId('demo_source', 'abc123');

    test(
        'defaults to nothing, so a provider that predates the field is '
        'unaffected', () {
      final track = SwayveTrack(id: id, title: 'Nightdrive');
      expect(track.alternateNames, SwayveAlternateNames.none);
      expect(track.toJson().containsKey('alternateNames'), isFalse);
      expect(SwayveTrack.fromJson(track.toJson()), track);
    });

    test('round trips when a provider publishes some', () {
      final track = SwayveTrack(
        id: id,
        title: 'おやすみがこわい',
        alternateNames: names,
      );
      final read = SwayveTrack.fromJson(track.toJson());
      expect(read, track);
      expect(read.alternateNames.romanizedTitle, 'Oyasumi ga Kowai');
      // The canonical title is untouched by any of it, which is the whole
      // point: a romanization sits beside the name the record has, never in
      // place of it.
      expect(read.title, 'おやすみがこわい');
    });

    test('two tracks differing only in their alternate names are not equal',
        () {
      final bare = SwayveTrack(id: id, title: 'おやすみがこわい');
      expect(bare.copyWith(alternateNames: names) == bare, isFalse);
    });
  });
}
