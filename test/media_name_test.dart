import 'package:c411_remote/core/media_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  (String, int?, int?, int?) g(String path) {
    final m = MediaGuess.parse(path);
    return (m.title, m.year, m.season, m.episode);
  }

  test('épisodes', () {
    expect(g('/t/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E01.MULTi.1080p.WEB.H265-GRP.mkv'),
        ('The Bear', null, 3, 1));
    expect(g('/Séries/MobLand/Saison 1/MobLand - S01E02 - Chapitre 2.mkv'),
        ('MobLand', null, 1, 2));
    expect(g('/Séries/Crystal Lake (2025)/Season 01/S01E04.mkv'),
        ('Crystal Lake', 2025, 1, 4));
    expect(g('/t/Show.Name.2x05.HDTV.avi'), ('Show Name', null, 2, 5));
    expect(g('/t/Dexter.Resurrection.S01.FRENCH.1080p-GRP/dxr.s01e10.1080p.mkv'),
        ('Dexter Resurrection', null, 1, 10));
  });

  test('films', () {
    expect(g('/t/Dune.Part.Two.2024.MULTi.2160p.WEB.H265-GRP.mkv'),
        ('Dune Part Two', 2024, null, null));
    expect(g('/t/Le.Comte.de.Monte-Cristo.2024.FRENCH.1080p-GRP/grp-lcdmc-1080p.mkv'),
        ('Le Comte de Monte-Cristo', 2024, null, null));
    expect(g('/Films/Amélie (2001) [1080p].mkv'), ('Amélie', 2001, null, null));
    expect(MediaGuess.parse('/t/Dune.2021.2160p.mkv').resolution, '2160p');
  });

  test('extraits et bonus ignorés', () {
    expect(MediaGuess.isExtra('/t/Film.2024/Sample/film.sample.mkv'), isTrue);
    expect(MediaGuess.isExtra('/t/Film.2024/film-sample.mkv'), isTrue);
    expect(MediaGuess.isExtra('/t/Film.2024/Extras/Making of.mkv'), isTrue);
    expect(MediaGuess.isExtra('/t/Samples.Of.Life.2024.mkv'), isFalse);
    expect(isVideoPath('/a/b.MKV'), isTrue);
    expect(isVideoPath('/a/b.nfo'), isFalse);
  });
}
