import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
import 'package:c411_remote/ui/series_page.dart';
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
    // Un seul bouton de lecture, sur l'affiche ; plus de « Chercher sur les
    // trackers » (la disponibilité s'affiche d'office).
    expect(find.byTooltip('Lire'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Lire'), findsNothing);
    expect(find.text('Chercher sur les trackers'), findsNothing);
    expect(find.text('Déjà chez toi'), findsOneWidget);
    expect(find.text('Dune : Deuxième partie · 2024 · déjà vu'), findsOneWidget);
    expect(find.text('Dune.Deuxieme.Partie.2024.MULTI.VF2.2160p.WEB.H265-HYPERION'),
        findsOneWidget);
    expect(find.text('42,0 %'), findsOneWidget);
  });

  for (final (width, side) in [(1400.0, true), (600.0, false)]) {
    testWidgets('fiche d’un souhait : encadrés ${side ? 'côte à côte' : 'empilés'} '
        '(${width.toInt()} px)', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: TitleDetailPage(title: _dune2),
        ),
      ));
      await tester.pumpAndSettle();
      final owned = tester.getTopLeft(find.text('Déjà chez toi'));
      final dates = tester.getTopLeft(find.text('Sorties en France'));
      if (side) {
        expect(dates.dy, closeTo(owned.dy, 4), reason: 'même rangée');
        expect(dates.dx, greaterThan(owned.dx + 200));
      } else {
        expect(dates.dy, greaterThan(owned.dy + 40), reason: 'l’un sous l’autre');
      }
      expect(tester.takeException(), isNull);
    });
  }

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
        home: Scaffold(
            body: Center(
                child: PlayBadge(
                    item: Playable(
                        isSeries: true,
                        label: 'DANS JELLYFIN',
                        description: '',
                        play: (context) => playOnJellyfin(context, series))))),
      ),
    ));
    await tester.tap(find.byType(PlayBadge));
    await tester.pumpAndSettle();
    expect(find.text('The Bear'), findsOneWidget, reason: 'barre du haut');
    expect(find.text('The Bear (2022)'), findsOneWidget, reason: 'fiche');
    expect(find.text('Une cuisine à Chicago.'), findsOneWidget);
    // Saison 1 vue en entier, l'épisode 2 entamé : on ouvre sur lui.
    expect(find.text('Saison 1 (2)'), findsOneWidget);
    expect(find.text('Saison 2 (1)'), findsOneWidget);
    expect(find.text('2. Mains'), findsOneWidget);
    expect(find.text('Reprendre S01E02'), findsOneWidget);
    expect(find.text('VU'), findsOneWidget, reason: 'épisode 1');
    expect(find.text('À SUIVRE'), findsOneWidget);
    expect(find.text('44 min · 12/03/2024 · ★ 8,4'), findsNWidgets(2));

    // Autre saison.
    await tester.tap(find.text('Saison 2 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('1. Bœuf'), findsOneWidget);
    expect(find.text('2. Mains'), findsNothing);

    // Téléphone : le détail s'ouvre en bas.
    await tester.tap(find.text('1. Bœuf'));
    await tester.pumpAndSettle();
    expect(find.text('S02E01 · The Bear'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Lire'), findsOneWidget);
  });

  testWidgets('série sur PC : détail de l’épisode choisi à droite', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final series = JellyfinItem.fromApi(_item('s', 'The Bear', 2022, type: 'Series'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        jellyfinProvider.overrideWithValue(_Episodes()),
        playbackStoreProvider.overrideWithValue(MemoryPlaybackStore()),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: EpisodesPage(series: series),
      ),
    ));
    await tester.pumpAndSettle();
    // Panneau : l'épisode à suivre, puis celui qu'on touche.
    expect(find.text('S01E02 · The Bear'), findsOneWidget);
    await tester.tap(find.text('1. Système'));
    await tester.pumpAndSettle();
    expect(find.text('S01E01 · The Bear'), findsOneWidget);
    expect(find.text('Le chef revient.'), findsNWidgets(2), reason: 'carte et panneau');
    expect(tester.takeException(), isNull);
  });

  test('épisode à suivre et avancement', () {
    JellyfinItem ep(String id, {bool played = false, int? ticks}) => JellyfinItem.fromApi({
          'Id': id, 'Name': id, 'Type': 'Episode', 'RunTimeTicks': 36000000000, // 1 h
          'UserData': {'Played': played, 'PlaybackPositionTicks': ?ticks},
        });
    final eps = [ep('a', played: true), ep('b', played: true), ep('c'), ep('d')];
    expect(nextEpisode(eps, const {})?.id, 'c');
    expect(nextEpisode(eps, {'d'})?.id, 'd', reason: 'reprise locale');
    expect(nextEpisode([ep('x'), ep('y', ticks: 600000000)], const {})?.id, 'y');
    expect(nextEpisode([ep('a', played: true)], const {})?.id, 'a');
    expect(episodeProgress(ep('c'), {'c': const Duration(minutes: 15)}), 0.25);
    expect(episodeProgress(ep('a', played: true), const {}), 1);
    expect(episodeProgress(ep('d'), const {}), isNull);
  });

  test('versions : fichier, résolution, HDR, audio ; adresse par version', () {
    final item = JellyfinItem.fromApi(_item('dune', 'Dune', 2021));
    final v = JellyfinVersion.fromApi(item, {
      'Id': 'src4k', 'Name': '2160p', 'Container': 'mkv', 'Size': 43000000000,
      'Path': '/films/Dune (2021)/Dune - 2160p.mkv',
      'MediaStreams': [
        {'Type': 'Video', 'Codec': 'hevc', 'Width': 3840, 'Height': 1604,
         'VideoRange': 'HDR', 'VideoRangeType': 'DOVIWithHDR10'},
        {'Type': 'Audio', 'Codec': 'aac', 'DisplayTitle': 'AAC 2.0 · Anglais'},
        {'Type': 'Audio', 'Codec': 'truehd', 'IsDefault': true,
         'DisplayTitle': 'TrueHD Atmos 7.1 · Français'},
      ],
    });
    expect((v.resolution, v.videoCodec, v.hdr, v.audio, v.fileName),
        ('2160p', 'HEVC', 'Dolby Vision', 'TrueHD Atmos 7.1 · Français', 'Dune - 2160p.mkv'));
    final sdr = JellyfinVersion.fromApi(item, {
      'Id': 's', 'MediaStreams': [{'Type': 'Video', 'Width': 1920, 'VideoRange': 'SDR'}],
    });
    expect((sdr.resolution, sdr.hdr), ('1080p', null));
    expect(_client.streamUrl('dune', sourceId: 'src4k').toString(),
        'http://jelly.local:8096/Videos/dune/stream?static=true&mediaSourceId=src4k&api_key=k');
  });

  test('doublons : même identifiant TMDB, ou même titre et année', () {
    final lib = _library([
      _item('a', 'Dune', 2021, tmdb: '438631'),
      _item('b', 'Dune (4K)', 2021, tmdb: '438631'),
      _item('c', 'Dune', 1984, tmdb: '841'),
      _item('d', 'Sans id', 2020),
      _item('e', 'Sans id', 2020),
      _item('f', 'Sans id', 2020, type: 'Series'),
    ]);
    List<String> ids(String id) =>
        lib.versionsOf(lib.items.firstWhere((i) => i.id == id)).map((i) => i.id).toList();
    expect(ids('a'), ['a', 'b']);
    expect(ids('c'), ['c']);
    expect(ids('d'), ['d', 'e'], reason: 'pas la série du même nom');
  });

  testWidgets('plusieurs versions : choix, la meilleure d’abord', (tester) async {
    final item = JellyfinItem.fromApi(_item('dune', 'Dune', 2021));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        jellyfinProvider.overrideWithValue(_Versions()),
        playbackStoreProvider.overrideWithValue(
            MemoryPlaybackStore()..save({'hd': const Duration(minutes: 20)})),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
                onPressed: () => playVersions(context, [item], 'Dune (2021)'),
                child: const Text('go')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Quelle version ?'), findsOneWidget);
    expect(find.text('Dune (2021) · 2 versions sur le disque'), findsOneWidget);
    final uhd = find.textContaining('2160p · HEVC · HDR10');
    final hd = find.textContaining('1080p · H264');
    expect(tester.getTopLeft(uhd).dy, lessThan(tester.getTopLeft(hd).dy));
    expect(find.textContaining('lecture entamée'), findsOneWidget);
  });

  group('requêtes envoyées à Jellyfin', () {
    test('épisodes par /Items, au nom d’un administrateur, fichiers présents', () async {
      final net = _Net((o) => switch (o.path) {
            '/Users' => (200, [
                {'Id': 'u2', 'Policy': {'IsAdministrator': false}},
                {'Id': 'off', 'Policy': {'IsAdministrator': true, 'IsDisabled': true}},
                {'Id': 'u1', 'Policy': {'IsAdministrator': true}},
              ]),
            '/Items' => (200, {
                'Items': [
                  {'Id': 'e2', 'Name': 'B', 'Type': 'Episode', 'ParentIndexNumber': 1, 'IndexNumber': 2},
                  {'Id': 'e1', 'Name': 'A', 'Type': 'Episode', 'ParentIndexNumber': 1, 'IndexNumber': 1},
                ],
              }),
            _ => (404, {}),
          });
      final client = JellyfinClient(url: 'http://jelly.local', apiKey: 'k', adapter: net);
      final episodes = await client.episodes('crystal');
      expect(episodes.map((e) => e.id), ['e1', 'e2'], reason: 'dans l’ordre');
      final items = net.requests.where((o) => o.path == '/Items').single;
      expect(items.queryParameters, containsPair('ParentId', 'crystal'));
      expect(items.queryParameters, containsPair('IncludeItemTypes', 'Episode'));
      expect(items.queryParameters, containsPair('IsMissing', false));
      expect(items.queryParameters, containsPair('Recursive', true));
      expect(items.queryParameters, containsPair('userId', 'u1'));
      expect(net.requests.any((o) => o.path.startsWith('/Shows')), isFalse);

      await client.seasons('crystal');
      expect(net.requests.where((o) => o.path == '/Users'), hasLength(1),
          reason: 'utilisateur cherché une seule fois');
      expect(net.requests.last.queryParameters, containsPair('IncludeItemTypes', 'Season'));
    });

    test('épisodes : autres façons de demander quand /Items est vide', () async {
      final net = _Net((o) {
        if (o.path == '/Users') return (200, [{'Id': 'u1', 'Name': 'vache', 'Policy': {'IsAdministrator': true}}]);
        if (o.path == '/Items') {
          // Avec IsMissing=false : rien ; sans : un épisode réel, un virtuel.
          if (o.queryParameters['IsMissing'] == false) return (200, {'Items': []});
          return (200, {'Items': [
            {'Id': 'v', 'Name': 'Virtuel', 'Type': 'Episode', 'LocationType': 'Virtual'},
            {'Id': 'r', 'Name': 'Réel', 'Type': 'Episode', 'LocationType': 'FileSystem'},
          ]});
        }
        if (o.path.startsWith('/Shows/')) return (200, {'Items': []});
        return (404, {});
      });
      final client = JellyfinClient(url: 'http://jelly.local', apiKey: 'secret', adapter: net);
      expect((await client.episodes('mob')).map((e) => e.id), ['r']);
      expect(net.requests.map((o) => o.path), containsAllInOrder(['/Items', '/Shows/mob/Episodes', '/Items']));

      // /Shows répond : on s'arrête là.
      final shows = _Net((o) => switch (o.path) {
            '/Items' => (200, {'Items': []}),
            '/Shows/mob/Episodes' => (200, {'Items': [{'Id': 's1', 'Name': 'Un', 'Type': 'Episode'}]}),
            _ => (404, {}),
          });
      final c2 = JellyfinClient(url: 'http://jelly.local', apiKey: 'secret', adapter: shows);
      expect((await c2.episodes('mob')).map((e) => e.id), ['s1']);
    });

    test('bibliothèque mixte : dossiers au nom de la sortie, une saison chacun',
        () async {
      const s1 = 'MobLand.2025.S01.MULTI.VFF.1080p.WEBRip.EAC3.5.1.x265-ZAKARI';
      const dir = '/APPBOX_DATA/apps/tor.x/torrents/completed';
      final net = _Net((o) {
        final q = o.queryParameters;
        if (o.path == '/Users') return (200, [{'Id': 'u1', 'Name': 'vache', 'Policy': {'IsAdministrator': true}}]);
        if (o.path != '/Items') return (404, {});
        if (q['searchTerm'] != null) {
          return (200, {'Items': [
            {'Id': 'a', 'Name': s1, 'Type': 'Folder', 'Path': '$dir/$s1'},
            {'Id': 'b', 'Name': 'MobLand.S02.FRENCH.1080p-GRP', 'Type': 'Folder'},
            {'Id': 'c', 'Name': 'MobLander.2025.1080p-GRP', 'Type': 'Folder'},
          ]});
        }
        if (q['IncludeItemTypes'] == 'Episode,Video,Movie') {
          return (200, {'Items': switch (q['ParentId']) {
            'a' => [
                {'Id': 'e2', 'Name': 'MobLand', 'Type': 'Movie',
                 'Path': '$dir/$s1/MobLand (2025) - S01E02 - Jigsaw Puzzle [MULTi][WEBRip-1080p].mkv'},
                {'Id': 'e1', 'Name': 'MobLand', 'Type': 'Movie',
                 'Path': '$dir/$s1/MobLand (2025) - S01E01 - Stick or Twist [MULTi][WEBRip-1080p].mkv'},
              ],
            'b' => [{'Id': 'f1', 'Name': 'MobLand.S02E01.1080p', 'Type': 'Video'}],
            _ => [],
          }});
        }
        return (200, {'Items': []});
      });
      final client = JellyfinClient(url: 'http://jelly.local', apiKey: 'k', adapter: net);
      const mob = TmdbTitle(id: 247718, type: TmdbType.tv, title: 'MobLand');
      final container = ProviderContainer(overrides: [
        jellyfinProvider.overrideWithValue(client),
        jellyfinLibraryProvider.overrideWith((ref) async => _library([])),
      ]);
      addTearDown(container.dispose);

      final folder = await container.read(jellyfinItemProvider(mob).future);
      expect((folder?.id, folder?.isSeries), ('a', true));
      final show = await container.read(jellyfinShowProvider(folder!).future);
      expect(show.episodes.map((e) => (e.id, e.season, e.episode)),
          [('e1', 1, 1), ('e2', 1, 2), ('f1', 2, 1)]);
      expect(show.episodes.map((e) => e.name),
          ['Stick or Twist', 'Jigsaw Puzzle', 'MobLand.S02E01.1080p']);
    });

    test('bibliothèque mixte : dossier de la série, vidéos numérotées par leur nom',
        () async {
      final net = _Net((o) {
        final q = o.queryParameters;
        if (o.path == '/Users') return (200, [{'Id': 'u1', 'Name': 'vache', 'Policy': {'IsAdministrator': true}}]);
        if (o.path != '/Items') return (404, {});
        if (q['searchTerm'] != null) {
          return (200, {'Items': [
            {'Id': 'f', 'Name': 'MobLand (2025)', 'Type': 'Folder', 'Path': '/media/Mixte/MobLand (2025)'},
            {'Id': 'x', 'Name': 'MobLand.S01E01.1080p', 'Type': 'Video'},
          ]});
        }
        if (q['ParentId'] == 'f' && q['IncludeItemTypes'] == 'Episode,Video,Movie') {
          return (200, {'Items': [
            {'Id': 'v1', 'Name': 'MobLand.S01E02.1080p.WEB', 'Type': 'Video'},
            {'Id': 'v2', 'Name': 'Épisode', 'Type': 'Movie',
             'Path': '/media/Mixte/MobLand (2025)/Saison 1/MobLand - 1x01.mkv'},
          ]});
        }
        return (200, {'Items': []});
      });
      final client = JellyfinClient(url: 'http://jelly.local', apiKey: 'k', adapter: net);
      const mob = TmdbTitle(id: 247718, type: TmdbType.tv, title: 'MobLand');
      final container = ProviderContainer(overrides: [
        jellyfinProvider.overrideWithValue(client),
        jellyfinLibraryProvider.overrideWith((ref) async => _library([])),
      ]);
      addTearDown(container.dispose);

      final folder = await container.read(jellyfinItemProvider(mob).future);
      expect((folder?.id, folder?.isSeries), ('f', true));
      final show = await container.read(jellyfinShowProvider(folder!).future);
      expect(show.episodes.map((e) => (e.id, e.season, e.episode)),
          [('v2', 1, 1), ('v1', 1, 2)]);
    });

    test('série en double : épisodes des deux fiches réunis', () async {
      final net = _Net((o) {
        if (o.path != '/Items') return (404, {});
        final parent = o.queryParameters['ParentId'];
        if (o.queryParameters['IncludeItemTypes'] != 'Episode') return (200, {'Items': []});
        return (200, {'Items': [
          if (parent == 'vide') ...[],
          if (parent == 'plein') ...[
            {'Id': 'e1', 'Name': 'Un', 'Type': 'Episode', 'ParentIndexNumber': 1, 'IndexNumber': 1},
            {'Id': 'e2', 'Name': 'Deux', 'Type': 'Episode', 'ParentIndexNumber': 1, 'IndexNumber': 2},
          ],
        ]});
      });
      final client = JellyfinClient(url: 'http://jelly.local', apiKey: 'k', adapter: net);
      final vide = JellyfinItem.fromApi(_item('vide', 'MobLand', 2025, type: 'Series', tmdb: '247718'));
      final container = ProviderContainer(overrides: [
        jellyfinProvider.overrideWithValue(client),
        jellyfinLibraryProvider.overrideWith((ref) async => _library([
              _item('vide', 'MobLand', 2025, type: 'Series', tmdb: '247718'),
              _item('plein', 'MobLand', 2025, type: 'Series', tmdb: '247718'),
            ])),
      ]);
      addTearDown(container.dispose);
      await container.read(jellyfinLibraryProvider.future);
      final show = await container.read(jellyfinShowProvider(vide).future);
      expect(show.episodes.map((e) => e.id), ['e1', 'e2']);
    });

    test('sans /Users : requêtes sans utilisateur', () async {
      final net = _Net((o) => o.path == '/Items' ? (200, {'Items': []}) : (403, {}));
      final client = JellyfinClient(url: 'http://jelly.local', apiKey: 'k', adapter: net);
      await client.library();
      expect(net.requests.last.queryParameters.containsKey('userId'), isFalse);
    });
  });

  for (final known in [true, false]) {
    testWidgets('fiche d’une série : épisodes dans la fiche (${known ? 'reconnue' : 'inconnue'})',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const bear = TmdbTitle(id: 136315, type: TmdbType.tv, title: 'The Bear');
      await tester.pumpWidget(ProviderScope(
        overrides: [
          jellyfinProvider.overrideWithValue(_Episodes()),
          jellyfinLibraryProvider.overrideWith((ref) async => _library([
                if (known) _item('s', 'The Bear', 2022, type: 'Series', tmdb: '136315'),
              ])),
          playbackStoreProvider.overrideWithValue(MemoryPlaybackStore()),
          wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
          trackersProvider.overrideWithValue(const <Tracker, TrackerApi>{}),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const TitleDetailPage(title: bear),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Épisodes sur le disque'), 300,
          scrollable: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down));
      if (known) {
        expect(find.textContaining('Saison 1 (2)'), findsOneWidget);
        expect(find.text('2. Mains'), findsOneWidget, reason: 'saison à suivre');
        expect(find.text('Tout voir'), findsWidgets);
      } else {
        expect(find.text('Série pas trouvée dans ta bibliothèque Jellyfin.'), findsOneWidget);
        expect(find.text('Copier le diagnostic'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

class _Episodes extends JellyfinClient {
  _Episodes() : super(url: 'http://jelly.local', apiKey: 'k');

  @override
  Future<List<JellyfinItem>> episodes(String seriesId) async => [
        for (final (s, n, name, played, ticks, overview) in [
          (1, 1, 'Système', true, null, 'Le chef revient.'),
          (1, 2, 'Mains', false, 6000000000, null),
          (2, 1, 'Bœuf', false, null, null),
        ])
          JellyfinItem.fromApi({
            'Id': 'e$s$n', 'Name': name, 'Type': 'Episode',
            'ParentIndexNumber': s, 'IndexNumber': n, 'Overview': ?overview,
            'RunTimeTicks': 26400000000, 'PremiereDate': '2024-03-12T00:00:00Z',
            'CommunityRating': 8.4,
            'UserData': {'Played': played, 'PlaybackPositionTicks': ?ticks},
          }),
      ];

  @override
  Future<List<JellyfinSeason>> seasons(String seriesId) async => const [];

  @override
  Future<JellyfinItem?> details(String itemId) async => JellyfinItem.fromApi({
        'Id': itemId, 'Name': 'The Bear', 'Type': 'Series', 'ProductionYear': 2022,
        'Overview': 'Une cuisine à Chicago.', 'Genres': ['Drame'],
      });
}

class _Versions extends JellyfinClient {
  _Versions() : super(url: 'http://jelly.local', apiKey: 'k');

  @override
  Future<List<JellyfinVersion>> versions(List<JellyfinItem> items) async => [
        JellyfinVersion.fromApi(items.first, {
          'Id': 'hd', 'Size': 9000000000, 'Path': '/f/Dune - 1080p.mkv',
          'MediaStreams': [{'Type': 'Video', 'Codec': 'h264', 'Width': 1920}],
        }),
        JellyfinVersion.fromApi(items.first, {
          'Id': 'uhd', 'Size': 40000000000, 'Path': '/f/Dune - 2160p.mkv',
          'MediaStreams': [
            {'Type': 'Video', 'Codec': 'hevc', 'Width': 3840, 'VideoRangeType': 'HDR10'},
          ],
        }),
      ];
}

/// Couche réseau factice : enregistre les requêtes et répond en JSON.
class _Net implements HttpClientAdapter {
  _Net(this.respond);
  final (int, Object) Function(RequestOptions o) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = respond(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
