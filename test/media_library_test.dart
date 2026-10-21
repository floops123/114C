import 'package:c411_remote/api/ftp.dart';
import 'package:c411_remote/api/tmdb.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:c411_remote/state/playback.dart';
import 'package:c411_remote/ui/disk_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp.dart';

const _dir = '/APPBOX_DATA/apps/transmission.moi/torrents';

class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: [
          {
            'id': 1,
            'hashString': 'aaa',
            'downloadDir': _dir,
            'percentDone': 1.0,
            'files': [
              {'name': 'Dune.Part.Two.2024.MULTi.2160p.WEB-GRP.mkv', 'length': _go2},
            ],
          },
          {
            'id': 2,
            'hashString': 'bbb',
            'downloadDir': _dir,
            'percentDone': 1.0,
            'files': [
              {'name': 'The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E02.mkv', 'length': _mo700},
              {'name': 'The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E01.mkv', 'length': _mo600},
              {'name': 'The.Bear.S03.MULTi.1080p-GRP/info.nfo', 'length': 1},
            ],
          },
          {
            'id': 3,
            'hashString': 'ccc',
            'downloadDir': _dir,
            'percentDone': 0.5,
            'files': [
              {'name': 'En.Cours.2025.1080p.mkv', 'length': 9},
            ],
          },
        ],
        removed: <int>[],
      );
}

// Tailles réalistes : un film fait au moins 500 Mo, un épisode 100 Mo.
const _go2 = 2 << 30, _mo700 = 700 << 20, _mo600 = 600 << 20;

class _Tmdb extends TmdbApi {
  _Tmdb() : super('x');
  final asked = <String>[];

  @override
  Future<TmdbTitle?> identify(String query, TmdbType type, {int? year}) async {
    asked.add('${type.name}:$query:${year ?? ''}');
    return switch (query) {
      'Dune Part Two' => const TmdbTitle(id: 1, type: TmdbType.movie, title: 'Dune : Deuxième partie', originalTitle: 'Dune: Part Two'),
      'The Bear' => const TmdbTitle(id: 2, type: TmdbType.tv, title: 'The Bear'),
      _ => null,
    };
  }
}

class _SeasonTmdb extends TmdbApi {
  _SeasonTmdb() : super('x');
  @override
  Future<List<TmdbEpisode>> season(int tvId, int season) async => [
        TmdbEpisode(season: season, number: 1, name: 'Pilote', overview: 'Le début.', runtime: 42),
        TmdbEpisode(season: season, number: 2, name: 'La suite'),
      ];
}

class _Settings extends SettingsNotifier {
  _Settings(this.port);
  final int port;
  @override
  Future<AppSettings> build() async => AppSettings(
      ftpHost: '127.0.0.1',
      ftpPort: port,
      ftpUser: 'moi',
      ftpPassword: 'secret',
      ftpTls: false,
      mediaFolders: const ['/medias/']);
}

void main() {
  test('base : torrents terminés et dossiers du FTP, fiches TMDB', () async {
    final server = await FakeFtpServer.start({
      '/torrents/Dune.Part.Two.2024.MULTi.2160p.WEB-GRP.mkv': [1, 2, 3, 4, 5, 6],
      '/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E01.mkv': [1],
      '/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E02.mkv': [1, 2],
      '/medias/Films/Amélie (2001)/Amélie (2001).mkv': [1],
      '/medias/Films/Amélie (2001)/Sample/sample.mkv': [1],
      '/medias/Séries/MobLand/Saison 1/MobLand - S01E01.mkv': [1],
      // Vidéo de jeu : trop petite pour un film, écartée.
      '/medias/Jeux/vectrex/videos/Mine Storm-video.mp4': [1],
    }, sizes: {
      '/torrents/Dune.Part.Two.2024.MULTi.2160p.WEB-GRP.mkv': _go2,
      '/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E01.mkv': _mo600,
      '/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E02.mkv': _mo700,
      '/medias/Films/Amélie (2001)/Amélie (2001).mkv': _go2,
      // Épisode court en H.265 : gardé (au moins 100 Mo).
      '/medias/Séries/MobLand/Saison 1/MobLand - S01E01.mkv': 211 << 20,
      '/medias/Jeux/vectrex/videos/Mine Storm-video.mp4': 3 << 20,
    });
    addTearDown(server.close);
    final tmdb = _Tmdb();
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Settings(server.port)),
      transmissionProvider.overrideWithValue(_Transmission()),
      tmdbProvider.overrideWithValue(tmdb),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(mediaLibraryProvider.notifier).scan();

    final state = container.read(mediaLibraryProvider);
    expect(state.error, isNull);
    final library = state.library;
    expect((library.pathFrom, library.pathTo), ('/APPBOX_DATA/apps/transmission.moi', ''));
    expect(library.files.map((f) => f.path).toSet(), {
      '/torrents/Dune.Part.Two.2024.MULTi.2160p.WEB-GRP.mkv',
      '/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E01.mkv',
      '/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E02.mkv',
      '/medias/Films/Amélie (2001)/Amélie (2001).mkv',
      '/medias/Séries/MobLand/Saison 1/MobLand - S01E01.mkv',
    });
    expect(tmdb.asked.toSet(), {
      'movie:Dune Part Two:2024', 'tv:The Bear:', 'movie:Amélie:2001', 'tv:MobLand:',
    });

    final titles = {for (final t in library.titles) t.title: t};
    expect(titles.keys.toSet(), {'Dune : Deuxième partie', 'The Bear', 'Amélie', 'MobLand'});
    final bear = titles['The Bear']!;
    expect(bear.isSeries, isTrue);
    expect(bear.seasons.keys, [3]);
    expect(bear.seasons[3]!.map((f) => f.guess.episode), [1, 2]);
    expect(bear.files.first.hash, 'bbb');

    // Fiche TMDB → titre de la base (par l'identifiant, ou par le nom).
    expect(library.forTmdb(const TmdbTitle(id: 1, type: TmdbType.movie, title: 'x'))?.title,
        'Dune : Deuxième partie');
    expect(library.forTmdb(TmdbTitle(id: 9, type: TmdbType.tv, title: 'MobLand', date: DateTime(2025)))?.title,
        'MobLand');
    expect(library.forTmdb(TmdbTitle(id: 8, type: TmdbType.movie, title: 'Amélie', date: DateTime(2010))),
        isNull, reason: 'autre année');

    // Sortie d'un tracker → titre de la base.
    Release release(String name, {String? hash}) => Release(
        tracker: Tracker.c411, id: name, name: name, infoHash: hash, createdAt: DateTime(2026));
    expect(library.forRelease(release('Dune.Part.Two.2024.MULTi.2160p.WEB-GRP'))?.title,
        'Dune : Deuxième partie');
    expect(library.forRelease(release('Autre', hash: 'BBB'))?.title, 'The Bear');
    expect(library.forRelease(release('MobLand.S01.FRENCH.1080p-GRP'))?.title, 'MobLand');
    expect(library.forRelease(release('Amelie.2001.1080p.BluRay-GRP'))?.title, 'Amélie');
    expect(library.forRelease(release('Amelie.1990.1080p-GRP')), isNull);

    // Rangée sur l'appareil : relue telle quelle.
    final reloaded = MediaLibrary.fromJson(library.toJson());
    expect(reloaded.titles.length, 4);
    expect(reloaded.files.every((f) => f.added != null), isTrue);
  });

  test('parcours sans Transmission : FTP injoignable', () async {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Settings(1)),
      transmissionProvider.overrideWithValue(null),
      tmdbProvider.overrideWithValue(null),
      ftpConnectProvider.overrideWithValue(
          (_) async => throw const FtpException('Serveur FTP injoignable')),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(mediaLibraryProvider.notifier).scan();
    expect(container.read(mediaLibraryProvider).error, 'Serveur FTP injoignable');
    expect(container.read(mediaLibraryProvider).scanning, isFalse);
  });

  testWidgets('vidéothèque : cartes, puis épisodes d’une série (petit écran)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = MediaLibrary(
      files: [
        MediaFile(path: '/t/Film.Inconnu.2020.1080p.mkv', size: 1 << 30, added: DateTime(2026, 1, 1)),
        MediaFile(path: '/t/The.Bear.S03.1080p-GRP/The.Bear.S03E01.mkv', size: 1 << 29, added: DateTime(2026, 2, 1)),
        MediaFile(path: '/t/The.Bear.S03.1080p-GRP/The.Bear.S03E02.mkv', size: 1 << 29, added: DateTime(2026, 2, 1)),
        MediaFile(path: '/t/The.Bear.S02E05.2160p.mkv', size: 1 << 29, added: DateTime(2026, 2, 1)),
      ],
      tmdb: {'tv:the bear': const TmdbTitle(id: 2, type: TmdbType.tv, title: 'The Bear')},
      scannedAt: DateTime.now(),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore(library)),
        tmdbProvider.overrideWithValue(_SeasonTmdb()),
        playbackStoreProvider.overrideWithValue(MemoryPlaybackStore()),
        settingsProvider.overrideWith(() => _Settings(1)),
        transmissionProvider.overrideWithValue(null),
        ftpConnectProvider.overrideWithValue(
            (_) async => throw const FtpException('hors ligne')),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        // Cartes de la rangée « Ta vidéothèque ».
        home: Scaffold(
          body: Consumer(
            builder: (_, ref, _) => Wrap(children: [
              for (final t in ref.watch(mediaLibraryProvider).library.titles)
                SizedBox(width: 112, height: 220, child: LocalTitleCard(title: t)),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('The Bear'), findsOneWidget);
    expect(find.text('Film Inconnu'), findsOneWidget);
    expect(find.text('2020 · 1080p'), findsOneWidget);
    expect(find.text('3 épisodes'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Série sans fiche ouverte ici : le bouton lecture ouvre les épisodes.
    await tester.tap(find.byIcon(Icons.video_library_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Saison 3 (2)'), findsOneWidget);
    expect(find.text('Saison 2 (1)'), findsOneWidget);
    expect(find.text('1. Pilote'), findsOneWidget);
    expect(find.text('Le début.'), findsOneWidget);
    expect(find.text('2. La suite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
