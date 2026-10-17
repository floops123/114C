import 'package:c411_remote/api/torznab.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/core/release_name.dart';
import 'package:c411_remote/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReleaseName', () {
    test('film', () {
      final r = ReleaseName.parse(
          'L.Ombre.D.Emily.2.2025.MULTI.VF2.1080p.BluRay.EAC3.5.1.x265-NoTag');
      expect(r.title, 'L Ombre D Emily 2');
      expect(r.year, 2025);
      expect(r.resolution, '1080p');
      expect(r.source, 'BluRay');
      expect(r.videoCodec, 'H.265');
      expect(r.languages, ['MULTI', 'VF2']);
      expect(r.kind, '');
    });

    test('série', () {
      final r = ReleaseName.parse(
          'Outlander.Blood.of.My.Blood.S02E05.MULTi.VFF.2160p.WEB.EAC3.5.1.H265-BYOR');
      expect(r.title, 'Outlander Blood of My Blood');
      expect(r.kind, 'Série');
      expect(r.resolution, '2160p');
      expect(r.source, 'WEB');
    });

    test('nom sans motif reconnu', () {
      expect(ReleaseName.parse('Tribune de Geneve PDF').title,
          'Tribune de Geneve PDF');
    });
  });

  test('parseRfc822', () {
    expect(parseRfc822('Sat, 17 Oct 2026 01:55:38 +0000'),
        DateTime.utc(2026, 10, 17, 1, 55, 38));
    expect(parseRfc822('Sat, 17 Oct 2026 03:55:38 +0200'),
        DateTime.utc(2026, 10, 17, 1, 55, 38));
    expect(parseRfc822('Sat, 17 Oct 2026 01:55:38 GMT'),
        DateTime.utc(2026, 10, 17, 1, 55, 38));
    expect(parseRfc822('n importe quoi'), isNull);
  });

  test('tri local des sorties (trackers Torznab)', () {
    Release r(String name, int seeders, int size, int day) => Release(
        tracker: Tracker.tr4ker,
        id: name,
        name: name,
        seeders: seeders,
        size: size,
        createdAt: DateTime(2026, 10, day));
    final items = [r('b', 5, 300, 2), r('A', 9, 100, 1), r('c', 1, 200, 3)];
    List<String> sorted(ReleaseSort s, bool asc) => [
          for (final x in List.of(items)
            ..sort((a, b) => asc ? s.compare(a, b) : s.compare(b, a)))
            x.name,
        ];
    expect(sorted(ReleaseSort.seeders, false), ['A', 'b', 'c']);
    expect(sorted(ReleaseSort.size, true), ['A', 'c', 'b']);
    expect(sorted(ReleaseSort.name, true), ['A', 'b', 'c']);
    expect(sorted(ReleaseSort.date, false), ['c', 'b', 'A']);
  });

  test('taille des vignettes TMDB adaptée à l’affichage', () {
    const url = 'https://image.tmdb.org/t/p/w500/abc.jpg';
    expect(tmdbSized(url, 150), 'https://image.tmdb.org/t/p/w154/abc.jpg');
    expect(tmdbSized(url, 155), 'https://image.tmdb.org/t/p/w185/abc.jpg');
    expect(tmdbSized(url, 330), 'https://image.tmdb.org/t/p/w342/abc.jpg');
    expect(tmdbSized('https://image.tmdb.org/t/p/original/x.jpg', 2000),
        'https://image.tmdb.org/t/p/w780/x.jpg');
    expect(tmdbSized('https://c411.org/uploads/a.webp', 100),
        'https://c411.org/uploads/a.webp');
  });
}
