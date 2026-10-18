import 'dart:typed_data';

import 'package:c411_remote/api/tmdb.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/state/catalog.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:c411_remote/ui/trackers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tracker factice : sorties par page (sans recherche) ou par requête.
class _Tracker implements TrackerApi {
  _Tracker(this.tracker, {this.pages = const [], this.search = const {}});
  @override
  final Tracker tracker;
  final List<List<Release>> pages;
  final Map<String, List<Release>> search;
  final queries = <String>[];
  final requested = <int>[];

  @override
  List<ReleaseSort> get sorts => const [ReleaseSort.date, ReleaseSort.seeders];
  @override
  Set<ReleaseSort> get serverSorts => const {ReleaseSort.date, ReleaseSort.seeders};
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases({int page = 1, int perPage = 50, int? categoryId,
      int? subcategoryId, String query = '', ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    if (query.isNotEmpty) {
      queries.add(query);
      final r = search[query] ?? const [];
      return ReleasePage(r, 1, 1, r.length);
    }
    requested.add(page);
    final items = page <= pages.length ? pages[page - 1] : const <Release>[];
    return ReleasePage(items, page, pages.length, 0);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
  @override
  void close() {}
}

Release _r(Tracker t, String name,
        {String? title, String? original, String? kind, int? year, int seeders = 1, DateTime? at}) =>
    Release(
        tracker: t,
        id: '${t.name}-$name',
        name: name,
        title: title,
        originalTitle: original,
        mediaKind: kind,
        year: year,
        seeders: seeders,
        createdAt: at ?? DateTime(2026, 10, 1));

void main() {
  test('regroupement par titre : titre français et original, séries ; le reste à part', () {
    final groups = groupReleases([
      _r(Tracker.c411, 'Dune.Deuxieme.Partie.2024.MULTi.2160p.WEB-GRP',
          title: 'Dune : Deuxième partie', original: 'Dune: Part Two', kind: 'movie', year: 2024),
      _r(Tracker.tr4ker, 'Dune.Part.Two.2024.1080p.BluRay.x264-ABC'),
      _r(Tracker.astra, 'Dune.Part.Two.2024.MULTi.720p.WEB-XYZ'),
      _r(Tracker.tr4ker, 'Dune.1984.1080p.BluRay-OLD'),
      _r(Tracker.c411, 'MobLand.S01.MULTi.1080p-ZAKARI', title: 'MobLand', kind: 'tv', year: 2025),
      _r(Tracker.nostradamus, 'MobLand.S01E02.1080p.WEB-GRP'),
      _r(Tracker.c411, 'Artiste.Album.2024.FLAC', title: 'Album', kind: 'music'),
    ]);
    final byTitle = {for (final g in groups) '${g.title} ${g.year}': g};
    expect(byTitle.keys.toSet(),
        {'Dune : Deuxième partie 2024', 'Dune 1984', 'MobLand 2025', 'Album null'});
    expect(byTitle['Album null']!.type, isNull, reason: 'musique : pas de fiche TMDB');
    expect(byTitle['Album null']!.tmdbQuery, isNull);
    final dune = byTitle['Dune : Deuxième partie 2024']!;
    expect(dune.releases.length, 3);
    expect(dune.trackers, {Tracker.c411, Tracker.tr4ker, Tracker.astra});
    expect(dune.bestResolution, '2160p');
    expect(dune.tmdbQuery, (type: TmdbType.movie, title: 'Dune: Part Two', year: 2024));
    expect(byTitle['MobLand 2025']!.releases.length, 2, reason: 'saison et épisode');
    expect(byTitle['MobLand 2025']!.type, TmdbType.tv);
  });

  test('disponibilité : un tracker suffit, films à venir non vérifiés, mémorisée', () async {
    final dune = TmdbTitle(
        id: 1, type: TmdbType.movie, title: 'Dune : Deuxième partie',
        originalTitle: 'Dune: Part Two', date: DateTime(2024, 2, 27));
    final upcoming = TmdbTitle(id: 2, type: TmdbType.movie, title: 'Avenir', date: DateTime(2099));
    final astra = _Tracker(Tracker.astra, search: {
      'Dune.Part.Two': [_r(Tracker.astra, 'Dune.Part.Two.2024.1080p-GRP')],
    });
    final c411 = _Tracker(Tracker.c411);
    final store = MemoryAvailabilityStore();
    final container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.astra: astra}),
      availabilityStoreProvider.overrideWithValue(store),
      trackerLimitersProvider.overrideWithValue({
        for (final t in Tracker.values) t: RateLimiter(Duration.zero),
      }),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(availabilityProvider.notifier);
    notifier.request(dune);
    notifier.request(dune); // dédoublonné
    notifier.request(upcoming);
    await pumpEventQueue();
    final state = container.read(availabilityProvider);
    expect(state[dune.key]?.trackers, {Tracker.astra});
    expect(state.containsKey(upcoming.key), isFalse);
    expect(astra.queries, ['Dune.Deuxieme.partie', 'Dune.Part.Two']);
    expect(c411.queries, isEmpty, reason: 'trouvé avant C411');
    expect(store.load()[dune.key]?.any, isTrue);
  });

  test('tops : une page de chaque tracker à la fois, fusionnées', () async {
    final c411 = _Tracker(Tracker.c411, pages: [
      [_r(Tracker.c411, 'A.2024.1080p-G', title: 'A', kind: 'movie', year: 2024)],
      [_r(Tracker.c411, 'B.2024.1080p-G', title: 'B', kind: 'movie', year: 2024)],
    ]);
    final tr4ker = _Tracker(Tracker.tr4ker, pages: [
      [_r(Tracker.tr4ker, 'A.2024.2160p-H', seeders: 50)],
    ]);
    final container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.tr4ker: tr4ker}),
    ]);
    addTearDown(container.dispose);
    container.read(topTrackersProvider);
    await pumpEventQueue();
    var s = container.read(topTrackersProvider);
    expect(s.releases.length, 2);
    expect(s.hasMore, isTrue, reason: 'C411 a une page 2');
    await container.read(topTrackersProvider.notifier).loadMore();
    s = container.read(topTrackersProvider);
    expect(c411.requested, [1, 2]);
    expect(tr4ker.requested, [1], reason: 'tr4ker n’a qu’une page');
    expect(s.hasMore, isFalse);
    final groups = sortedGroups(s);
    expect(groups.map((g) => g.title), containsAll(['A', 'B']));
    expect(groups.firstWhere((g) => g.title == 'A').releases.length, 2);
  });

  testWidgets('vue Trackers : titres regroupés, versions par tracker', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c411 = _Tracker(Tracker.c411, pages: [
      [
        _r(Tracker.c411, 'Dune.Deuxieme.Partie.2024.MULTi.2160p.WEB-GRP',
            title: 'Dune : Deuxième partie', original: 'Dune: Part Two', kind: 'movie',
            year: 2024, seeders: 214),
      ],
    ]);
    final tr4ker = _Tracker(Tracker.tr4ker, pages: [
      [_r(Tracker.tr4ker, 'Dune.Part.Two.2024.1080p.BluRay.x264-ABC', seeders: 48)],
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.tr4ker: tr4ker}),
        tmdbProvider.overrideWithValue(null),
        mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore()),
        tmdbMatchStoreProvider.overrideWithValue(MemoryTmdbMatchStore()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const TrackersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsOneWidget);
    expect(find.text('Dune : Deuxième partie'), findsOneWidget);
    expect(find.text('2024 · 2 versions'), findsOneWidget);
    expect(find.text('C411, tr4ker · ▲ 214'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Pas sur le disque : ⬇ ouvre les versions, rangées par tracker.
    await tester.tap(find.byTooltip('Choisir une version à télécharger'));
    await tester.pumpAndSettle();
    expect(find.text('C411 (1)'), findsOneWidget);
    expect(find.text('tr4ker (1)'), findsOneWidget);
    expect(find.text('Dune.Part.Two.2024.1080p.BluRay.x264-ABC'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vue Trackers : filtre « Sur le disque »', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c411 = _Tracker(Tracker.c411, pages: [
      [
        _r(Tracker.c411, 'Amelie.2001.1080p.BluRay-GRP', title: 'Amélie', kind: 'movie', year: 2001),
        _r(Tracker.c411, 'Autre.Film.2020.1080p-GRP', title: 'Autre film', kind: 'movie', year: 2020),
      ],
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
        tmdbProvider.overrideWithValue(null),
        tmdbMatchStoreProvider.overrideWithValue(MemoryTmdbMatchStore()),
        mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore(MediaLibrary(
            files: [MediaFile(path: '/Films/Amélie (2001)/Amélie (2001).mkv', size: 1)],
            scannedAt: DateTime.now()))),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const TrackersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsNWidgets(2));
    expect(find.byTooltip('Lire'), findsOneWidget, reason: 'Amélie est sur le disque');

    await tester.tap(find.text('Sur le disque'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsOneWidget);
    expect(find.text('Amélie'), findsOneWidget);

    await tester.tap(find.text('À télécharger'));
    await tester.pumpAndSettle();
    expect(find.text('Autre film'), findsOneWidget);
    expect(find.text('Amélie'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vue Trackers : filtre par tracker et vue liste', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c411 = _Tracker(Tracker.c411, pages: [
      [
        _r(Tracker.c411, 'Dune.Part.Two.2024.MULTi.2160p.WEB-GRP',
            title: 'Dune : Deuxième partie', original: 'Dune: Part Two', kind: 'movie',
            year: 2024, seeders: 214),
        _r(Tracker.c411, 'Conclave.2024.1080p.WEB-GRP', title: 'Conclave', kind: 'movie', year: 2024),
      ],
    ]);
    final tr4ker = _Tracker(Tracker.tr4ker, pages: [
      [_r(Tracker.tr4ker, 'Dune.Part.Two.2024.1080p.BluRay.x264-ABC', seeders: 48)],
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.tr4ker: tr4ker}),
        tmdbProvider.overrideWithValue(null),
        mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore()),
        tmdbMatchStoreProvider.overrideWithValue(MemoryTmdbMatchStore()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const TrackersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tous les trackers (2)'), findsOneWidget);
    expect(find.text('C411 (2)'), findsOneWidget);
    expect(find.text('tr4ker (1)'), findsOneWidget);
    expect(find.byType(GroupCard), findsNWidgets(2));

    // tr4ker seul : un titre, et ses seules versions.
    await tester.tap(find.text('tr4ker (1)'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsOneWidget);
    expect(find.text('2024 · 1 version'), findsOneWidget);
    expect(find.text('tr4ker · ▲ 48'), findsOneWidget);

    // Vue liste : cartes façon Transferts.
    await tester.tap(find.text('Tous les trackers (2)'));
    await tester.tap(find.byTooltip('Affichage liste'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupTile), findsNWidgets(2));
    expect(find.text('C411 · tr4ker'), findsOneWidget);
    expect(find.text('2 versions'), findsOneWidget);
    expect(find.text('214'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vue Trackers : toutes les catégories, avec leur nombre', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c411 = _Tracker(Tracker.c411, pages: [
      [
        _r(Tracker.c411, 'Dune.2024.1080p-GRP', title: 'Dune', kind: 'movie', year: 2024),
        _r(Tracker.c411, 'MobLand.S01.1080p-GRP', title: 'MobLand', kind: 'tv', year: 2025),
        _r(Tracker.c411, 'Artiste.Album.2024.FLAC-GRP', title: 'Album', kind: 'music'),
        _r(Tracker.c411, 'Roman.Auteur.FR.EPUB-GRP'),
      ],
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
        tmdbProvider.overrideWithValue(null),
        mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore()),
        tmdbMatchStoreProvider.overrideWithValue(MemoryTmdbMatchStore()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const TrackersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsNWidgets(4));
    for (final chip in ['Tout (4)', 'Films (1)', 'Séries (1)', 'Musique (1)', 'Livres (1)']) {
      expect(find.text(chip), findsOneWidget, reason: chip);
    }
    expect(find.text('Jeux vidéo (0)'), findsNothing, reason: 'catégories absentes masquées');

    await tester.tap(find.text('Musique (1)'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
