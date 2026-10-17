import 'package:c411_remote/api/jellyfin.dart';
import 'package:c411_remote/api/tmdb.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/playback.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/state/wishlist.dart';
import 'package:c411_remote/ui/on_disk.dart';
import 'package:c411_remote/ui/player_page.dart';
import 'package:c411_remote/ui/releases_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:c411_remote/ui/wishlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item(String id, String name, int year,
        {String type = 'Movie', String? original, String? tmdb,
        bool played = false, double? percent}) =>
    {
      'Id': id, 'Name': name, 'Type': type, 'ProductionYear': year,
      'OriginalTitle': ?original, 'ServerId': 'srv',
      'ProviderIds': {'Tmdb': ?tmdb, 'Imdb': 'tt1'},
      'UserData': {'Played': played, 'PlayedPercentage': ?percent},
    };

JellyfinLibrary _library(List<Map<String, dynamic>> items) =>
    JellyfinLibrary([for (final i in items) JellyfinItem.fromApi(i)]);

final _client = JellyfinClient(url: 'http://jelly.local:8096/', apiKey: 'k');

final _dune2 = TmdbTitle(
    id: 693134, type: TmdbType.movie, title: 'Dune : Deuxième partie',
    originalTitle: 'Dune: Part Two', date: DateTime(2024, 2, 27));

Release _rel(String id, String name,
        {String? title, String? original, int? year, String? kind, String? hash}) =>
    Release(
        tracker: Tracker.c411, id: id, name: name, title: title,
        originalTitle: original, year: year, mediaKind: kind, infoHash: hash,
        createdAt: DateTime(2026));

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => TorrentsState(loaded: true, byId: {
        1: const Torrent({
          'id': 1, 'hashString': 'AAA', 'percentDone': 0.42, 'totalSize': 100,
          'name': 'Dune.Deuxieme.Partie.2024.MULTI.VF2.2160p.WEB.H265-HYPERION',
        }),
        2: const Torrent({
          'id': 2, 'hashString': 'fini', 'percentDone': 1.0, 'totalSize': 100,
          'name': 'Autre.Film.2020.1080p-GRP',
        }),
      });
  @override
  Future<void> refresh({bool full = false}) async {}
}

void main() {
  test('élément Jellyfin : identifiants, lecture entamée', () {
    final i = JellyfinItem.fromApi(_item('x', 'Dune', 2021, tmdb: '438631', percent: 37.5));
    expect((i.id, i.name, i.year, i.tmdbId, i.serverId, i.played),
        ('x', 'Dune', 2021, '438631', 'srv', false));
    expect(i.progress, 0.375);
    expect(JellyfinItem.fromApi(_item('y', 'A', 2000)).progress, isNull);
    // Flux du fichier d'origine, sans transcodage.
    expect(_client.streamUrl('x').toString(),
        'http://jelly.local:8096/Videos/x/stream?static=true&api_key=k');
    expect(_client.headers, {'X-Emby-Token': 'k'});
  });

  test('titre TMDB : identifiant d’abord, puis titre et année', () {
    final lib = _library([
      _item('autre', 'Dune : Deuxième partie', 1990),
      _item('bon', 'Dune : Deuxième partie', 2024, tmdb: '693134'),
    ]);
    expect(lib.find(_dune2)?.id, 'bon');

    // Sans identifiant : nom (ou titre original) et année à un an près.
    final byName = _library([
      _item('vieux', 'Dune : Deuxième partie', 1990),
      _item('ok', 'Dune', 2025, original: 'Dune: Part Two'),
    ]);
    expect(byName.find(_dune2)?.id, 'ok');
    expect(_library([]).find(_dune2), isNull);
    // Une série du même nom n'est pas le film.
    expect(_library([_item('s', 'Dune: Part Two', 2024, type: 'Series')]).find(_dune2),
        isNull);
  });

  test('sortie de tracker : fiche, nom, série, musique', () {
    final lib = _library([
      _item('dune2', 'Dune : Deuxième partie', 2024, original: 'Dune: Part Two'),
      _item('serie', 'The Bear', 2022, type: 'Series'),
      _item('album', 'Discovery', 2001),
    ]);
    // C411 : titres de la fiche.
    expect(lib.forRelease(_rel('a', 'Dune.Deuxieme.Partie.2024.MULTI-G',
            title: 'Dune : Deuxième partie', original: 'Dune: Part Two',
            year: 2024, kind: 'movie'))?.id,
        'dune2');
    // Autre tracker : titre et année lus dans le nom (titre original).
    expect(lib.forRelease(_rel('b', 'Dune.Part.Two.2024.1080p.BluRay-G'))?.id, 'dune2');
    expect(lib.forRelease(_rel('c', 'Dune.Part.Two.1984.1080p-G')), isNull,
        reason: 'autre année');
    expect(lib.forRelease(_rel('d', 'The.Bear.S03E01.1080p.WEB-G'))?.id, 'serie');
    expect(lib.forRelease(_rel('e', 'Daft.Punk.Discovery.2001.FLAC-G',
            title: 'Discovery', year: 2001, kind: 'music')),
        isNull, reason: 'musique');
  });

  test('torrents de Transmission correspondant au titre', () {
    Torrent t(String hash, String name, [double done = 1]) =>
        Torrent({'hashString': hash, 'name': name, 'percentDone': done});
    final torrents = [
      t('a', 'Dune.Deuxieme.Partie.2024.MULTI.2160p.WEB-DL-GRP'),
      t('b', 'Dune.Part.Two.2024.1080p.BluRay.x264-GRP'),
      t('c', 'Dune.2021.MULTI.2160p-GRP'),
      t('d', 'Dune.Deuxieme.Partie.1984.VHS-GRP'), // autre année
      t('e', 'Nom.Sans.Rapport-GRP'), // retrouvé par infohash
    ];
    expect(torrentsForTitle(torrents, _dune2, known: {'e'}).map((t) => t.hash),
        ['a', 'b', 'e']);
  });

  final overrides = [
    jellyfinProvider.overrideWithValue(_client),
    jellyfinLibraryProvider.overrideWith((ref) async => _library([
          _item('bon', 'Dune : Deuxième partie', 2024,
              original: 'Dune: Part Two', tmdb: '693134', played: true),
        ])),
    torrentsProvider.overrideWith(_Torrents.new),
    trackersProvider.overrideWithValue(const <Tracker, TrackerApi>{}),
    wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
  ];

  testWidgets('fiche d’un souhait : Lire sur Jellyfin, téléchargement en cours',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: TitleDetailPage(title: _dune2),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Lire'), findsOneWidget);
    expect(find.text('Déjà chez toi'), findsOneWidget);
    expect(find.text('Dune : Deuxième partie · 2024 · déjà vu'), findsOneWidget);
    expect(find.text('Dune.Deuxieme.Partie.2024.MULTI.VF2.2160p.WEB.H265-HYPERION'),
        findsOneWidget);
    expect(find.text('42,0 %'), findsOneWidget);
  });

  testWidgets('Sorties : lecture depuis la ligne et la carte, « sur le disque »',
      (tester) async {
    final dune = _rel('a', 'Dune.Deuxieme.Partie.2024.MULTI.2160p-G',
        title: 'Dune : Deuxième partie', year: 2024, kind: 'movie');
    final fini = _rel('b', 'Autre.Film.2020.1080p-GRP',
        title: 'Autre film', year: 2020, kind: 'movie', hash: 'fini');
    final rien = _rel('c', 'Inconnu.2020.1080p-GRP',
        title: 'Inconnu', year: 2020, kind: 'movie');
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: ListView(children: [
            ReleaseRow(release: dune),
            ReleaseRow(release: fini),
            ReleaseRow(release: rien),
            SizedBox(height: 300, width: 200, child: ReleaseCard(release: dune)),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('DANS JELLYFIN'), findsOneWidget);
    expect(find.text('SUR LE DISQUE'), findsOneWidget, reason: 'torrent terminé');
    expect(find.byType(PlayBadge), findsNWidgets(2), reason: 'ligne et carte');
  });

  test('épisodes : saison, numéro, reprise ; titre du lecteur', () {
    final e = JellyfinItem.fromApi({
      'Id': 'ep', 'Name': 'Demain', 'Type': 'Episode', 'ParentIndexNumber': 3,
      'IndexNumber': 1, 'Overview': 'Résumé',
      'UserData': {'PlaybackPositionTicks': 6000000000}, // 10 min
    });
    expect((e.season, e.episode, e.overview, e.resume),
        (3, 1, 'Résumé', const Duration(minutes: 10)));
    final series = JellyfinItem.fromApi(_item('s', 'The Bear', 2022, type: 'Series'));
    expect(series.isSeries, isTrue);
    expect(episodeTitle(series, e), 'The Bear · S03E01 · Demain');
  });

  test('reprise : ni le tout début ni la fin', () {
    const h = Duration(hours: 2);
    expect(resumePoint(const Duration(seconds: 10), h), isNull);
    expect(resumePoint(const Duration(minutes: 40), h), const Duration(minutes: 40));
    expect(resumePoint(const Duration(minutes: 117), h), isNull, reason: 'terminé');
    final store = MemoryPlaybackStore()..save({'x': const Duration(minutes: 3)});
    expect(store.load(), {'x': const Duration(minutes: 3)});
  });

  testWidgets('série : le bouton lecture ouvre la liste des épisodes',
      (tester) async {
    final series = JellyfinItem.fromApi(_item('s', 'The Bear', 2022, type: 'Series'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        jellyfinProvider.overrideWithValue(_Episodes()),
        playbackStoreProvider.overrideWithValue(MemoryPlaybackStore()),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Center(child: PlayBadge(item: series))),
      ),
    ));
    await tester.tap(find.byType(PlayBadge));
    await tester.pumpAndSettle();
    expect(find.text('The Bear'), findsOneWidget);
    expect(find.text('Saison 1'), findsOneWidget);
    expect(find.text('Saison 2'), findsOneWidget);
    expect(find.text('1. Système'), findsOneWidget);
  });
}

class _Episodes extends JellyfinClient {
  _Episodes() : super(url: 'http://jelly.local', apiKey: 'k');

  @override
  Future<List<JellyfinItem>> episodes(String seriesId) async => [
        for (final (s, n, name) in [(1, 1, 'Système'), (1, 2, 'Mains'), (2, 1, 'Bœuf')])
          JellyfinItem.fromApi({
            'Id': 'e$s$n', 'Name': name, 'Type': 'Episode',
            'ParentIndexNumber': s, 'IndexNumber': n,
          }),
      ];
}
