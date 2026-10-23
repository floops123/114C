import 'dart:typed_data';

import 'package:c411_remote/api/content_kind.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/organize.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/organize_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transmission en mémoire : `torrent-set-location` déplace aussitôt.
class _Transmission extends TransmissionClient {
  _Transmission(this.torrents) : super(url: 'http://x');
  final List<Map<String, dynamic>> torrents;
  final moves = <(List<int>, String)>[];

  @override
  Future<Map<String, dynamic>> sessionGet() async => {'download-dir': '/data/'};

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: [
          for (final t in torrents)
            if (ids is! List || ids.contains(t['id'])) {...t},
        ],
        removed: <int>[],
      );

  @override
  Future<void> torrentSet(List<int> ids, Map<String, dynamic> args) async {
    for (final t in torrents) {
      if (ids.contains(t['id'])) t.addAll(args);
    }
  }

  @override
  Future<void> setLocation(List<int> ids, String location, {bool move = true}) async {
    moves.add((ids, location));
    for (final t in torrents) {
      if (ids.contains(t['id'])) t['downloadDir'] = location;
    }
  }
}

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true);
  @override
  Future<void> refresh({bool full = false}) async {}
}

/// C411 sans réseau : [items] pour toute recherche.
class _Tracker implements TrackerApi {
  _Tracker(this.items);
  final List<Release> items;
  final queries = <String>[];
  @override
  Tracker get tracker => Tracker.c411;
  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => const [ReleaseSort.date];
  @override
  Set<ReleaseSort> get serverSorts => const {};
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases(
      {int page = 1,
      int perPage = 50,
      int? categoryId,
      int? subcategoryId,
      String query = '',
      ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    queries.add(query);
    return ReleasePage(items, 1, 1, items.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

const _c411 = 'https://tracker.c411.org/announce/abc';

Map<String, dynamic> _t(int id, String name, String dir,
        {List<String> labels = const [], String? announce}) =>
    {
      'id': id,
      'name': name,
      'hashString': id.toRadixString(16).padLeft(40, '0'),
      'downloadDir': dir,
      'labels': labels,
      'status': 6,
      'totalSize': 1000,
      'trackers': [
        if (announce != null) {'announce': announce},
      ],
    };

void main() {
  test('dossier de catégorie sous la racine', () {
    expect(categoryFolder('/data/', ContentKind.movie), '/data/Films');
    expect(categoryFolder('/data', ContentKind.game), '/data/Jeux vidéo');
    expect(categoryFolder(r'D:\Torrents', ContentKind.series), r'D:\Torrents\Séries');
    expect(categoryFolder('/data', ContentKind.other), '/data');
  });

  test('étiquettes : la catégorie remplace l’ancienne, le reste est gardé', () {
    expect(relabel(['cross-seed', 'Films'], ContentKind.series), ['cross-seed', 'Séries']);
    expect(relabel(['Films'], ContentKind.other), isEmpty);
    expect(kindOfLabels(['reseed', 'Livres']), ContentKind.book);
    expect(kindOfLabels(['reseed']), isNull);
  });

  test('sous la racine', () {
    expect(insideRoot('/data', '/data/'), isTrue);
    expect(insideRoot('/data/Films/', '/data'), isTrue);
    expect(insideRoot('/database', '/data'), isFalse);
    expect(insideRoot('/media/films', '/data'), isFalse);
  });

  test('nouvel ajout : dossier de la catégorie, sauf dossier imposé', () async {
    final client = _Transmission([]);
    final auto = await client.categorized(const AddOptions(labels: ['x']), ContentKind.series);
    expect(auto.downloadDir, '/data/Séries');
    expect(auto.labels, ['x', 'Séries']);
    final chosen = await client.categorized(
        const AddOptions(downloadDir: '/ailleurs'), ContentKind.series);
    expect(chosen.downloadDir, '/ailleurs');
    expect(chosen.labels, ['Séries']);
  });

  test('relevé puis rangement : tracker, groupe de cross-seed, hors racine', () async {
    final torrents = [
      // Catégorie du tracker : un documentaire, que le nom ne dit pas.
      _t(1, 'Planete.Bleue.2020.1080p', '/data', announce: _c411),
      // Mêmes fichiers (cross-seed) : rangés ensemble.
      _t(2, 'Movie.2019.1080p', '/data'),
      _t(3, 'Movie.2019.1080p', '/data/', labels: ['cross-seed']),
      // Hors du dossier de téléchargement : pas coché d'office.
      _t(4, 'Other.2018.1080p', '/media/films'),
      // Déjà rangé.
      _t(5, 'Done.2017.1080p', '/data/Films', labels: ['Films']),
    ];
    final client = _Transmission(torrents);
    final tracker = _Tracker([
      Release(
        tracker: Tracker.c411,
        id: '1',
        name: 'Planete.Bleue.2020.1080p',
        infoHash: torrents[0]['hashString'] as String,
        subcategory: 'Documentaire',
        categories: const ['Films & Vidéos', 'Documentaire'],
        createdAt: DateTime(2026),
      ),
    ]);
    final cache = MemoryOrganizeCache();
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(client),
      trackersProvider.overrideWithValue({Tracker.c411: tracker}),
      torrentsProvider.overrideWith(_Torrents.new),
      organizeCacheProvider.overrideWithValue(cache),
      organizePollProvider.overrideWithValue(Duration.zero),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(organizeProvider.notifier);

    await notifier.scan();
    var state = container.read(organizeProvider);
    expect(state.root, '/data/');
    expect(state.groups, hasLength(4));
    OrganizeGroup group(String name) => container
        .read(organizeProvider)
        .groups
        .firstWhere((g) => g.name == name);
    expect(group('Planete.Bleue.2020.1080p').kind, ContentKind.documentary);
    expect(group('Planete.Bleue.2020.1080p').from, KindSource.tracker);
    expect(group('Movie.2019.1080p').torrents, hasLength(2));
    expect(group('Movie.2019.1080p').from, KindSource.name);
    expect(group('Done.2017.1080p').from, KindSource.label);
    expect(state.selected, {
      group('Planete.Bleue.2020.1080p').key,
      group('Movie.2019.1080p').key,
    });
    expect(cache.kinds, {torrents[0]['hashString']: 'documentary'});

    await notifier.apply(move: true);
    expect([for (final (ids, dir) in client.moves) '$ids $dir'], [
      '[2, 3] /data/Films',
      '[1] /data/Documentaires',
    ]);
    expect(torrents[0]['labels'], ['Documentaires']);
    expect(torrents[2]['labels'], ['cross-seed', 'Films']);
    expect(torrents[3]['downloadDir'], '/media/films');
    expect(torrents[3]['labels'], isEmpty);
    state = container.read(organizeProvider);
    expect(state.selected, isEmpty);
    expect(group('Movie.2019.1080p').step, OrganizeStep.done);
    expect(group('Movie.2019.1080p').needsMove(state.root), isFalse);

    // Relevé suivant : la catégorie du tracker vient de la mémoire.
    tracker.queries.clear();
    torrents[0]['labels'] = <String>[];
    await notifier.scan();
    expect(tracker.queries, isEmpty);
    expect(group('Planete.Bleue.2020.1080p').kind, ContentKind.documentary);
  });

  test('catégorie changée à la main : étiquettes seules', () async {
    final torrents = [_t(1, 'Some.Thing', '/data')];
    final client = _Transmission(torrents);
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(client),
      trackersProvider.overrideWithValue(const {}),
      torrentsProvider.overrideWith(_Torrents.new),
      organizeCacheProvider.overrideWithValue(MemoryOrganizeCache()),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(organizeProvider.notifier);
    await notifier.scan();
    final g = container.read(organizeProvider).groups.single;
    expect(g.kind, ContentKind.other);
    expect(container.read(organizeProvider).selected, isEmpty);
    notifier.setKind(g.key, ContentKind.software);
    notifier.toggle(g.key);
    await notifier.apply(move: false);
    expect(torrents[0]['labels'], ['Logiciels']);
    expect(client.moves, isEmpty);
  });

  for (final width in [380.0, 1200.0]) {
    testWidgets('page Ranger par catégorie (largeur $width)', (tester) async {
      final torrents = [
        _t(1, 'Movie.2019.1080p', '/data'),
        _t(2, 'Movie.2019.1080p', '/data', labels: ['cross-seed']),
        _t(3, 'Un.Nom.Tres.Long.De.Torrent.Qui.Deborde.Sur.Plusieurs.Lignes.2020.MULTI.1080p.WEB.x264-GROUPE',
            '/media/films'),
      ];
      final container = ProviderContainer(overrides: [
        transmissionProvider.overrideWithValue(_Transmission(torrents)),
        trackersProvider.overrideWithValue(const {}),
        torrentsProvider.overrideWith(_Torrents.new),
        organizeCacheProvider.overrideWithValue(MemoryOrganizeCache()),
      ]);
      addTearDown(container.dispose);
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(Brightness.dark), home: const OrganizePage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Movie.2019.1080p'), findsOneWidget);
      expect(find.text('2 torrents, mêmes fichiers'), findsOneWidget);
      expect(find.text('/data  →  /data/Films'), findsOneWidget);
      expect(find.text('Étiqueter et déplacer (1)'), findsOneWidget);
      await tester.tap(find.textContaining('Hors du dossier'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Un.Nom.Tres.Long'), findsOneWidget);
    });
  }
}
