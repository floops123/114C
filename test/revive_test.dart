import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/cross_seed.dart';
import 'package:c411_remote/state/revive.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cross_seed_test.dart' show torrentFile;

class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');
  final added = <(Uint8List?, AddOptions)>[];

  @override
  Future<({bool added, String? hash})> addTorrentWithHash(
      {Uint8List? metainfo,
      String? filename,
      AddOptions options = const AddOptions()}) async {
    added.add((metainfo, options));
    return (added: true, hash: 'tr${added.length}');
  }
}

/// C411 : pages triées par seeders croissants ; tr4ker : recherche par nom.
class _Tracker implements TrackerApi {
  _Tracker(this.tracker, {this.pages = const [], this.results = const {}});
  @override
  final Tracker tracker;
  final List<List<Release>> pages;
  final Map<String, List<Release>> results;
  final files = <String, Uint8List>{};
  final requested = <int>[];
  final queries = <String>[];

  @override
  List<ReleaseSort> get sorts => const [];
  @override
  /// Comme les vrais : C411 trie par seeders, Torznab non.
  Set<ReleaseSort> get serverSorts =>
      tracker == Tracker.c411 ? const {ReleaseSort.seeders} : const {};
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases({int page = 1, int perPage = 50, int? categoryId,
      int? subcategoryId, String query = '', ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    if (query.isNotEmpty) {
      queries.add(query);
      final r = results[query] ?? const [];
      return ReleasePage(r, 1, 1, r.length);
    }
    expect(sort, ReleaseSort.seeders);
    expect(ascending, isTrue);
    expect(categoryId, 7);
    requested.add(page);
    return ReleasePage(pages[page - 1], page, pages.length, 0);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => files[release.id]!;
}

Release _rel(Tracker t, String id, String name, int size, int seeders) => Release(
    tracker: t, id: id, name: name, size: size, seeders: seeders,
    infoHash: 'h$id', createdAt: DateTime(2026));

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true, hashes: {'hc4'});
  @override
  Future<void> refresh({bool full = false}) async {}
  void emit(TorrentsState s) => state = s;
}

void main() {
  test('sorties C411 sans seeder retrouvées sur tr4ker / AstraTorrent, puis cross-seed', () async {
    final c411 = _Tracker(Tracker.c411, pages: [
      [
        _rel(Tracker.c411, 'c1', 'Film.A-GRP', 100, 0),
        _rel(Tracker.c411, 'c2', 'Film.B-GRP', 200, 0),
      ],
      [
        _rel(Tracker.c411, 'c3', 'Film.C-GRP', 300, 0),
        _rel(Tracker.c411, 'c4', 'Film.D-GRP', 400, 0),
        _rel(Tracker.c411, 'c5', 'Film.E-GRP', 500, 2),
      ],
      [_rel(Tracker.c411, 'c6', 'Film.F-GRP', 600, 9)],
    ])
      ..files['c1'] = torrentFile('Film.A-GRP', [(['a.mkv'], 100)]);
    final tr4ker = _Tracker(Tracker.tr4ker, results: {
      'Film.A-GRP': [
        _rel(Tracker.tr4ker, 't0', 'Film.A-GRP', 100, 1),
        _rel(Tracker.tr4ker, 't1', 'Film.A-GRP', 100, 5),
        _rel(Tracker.tr4ker, 't9', 'Film.A.REPACK-GRP', 101, 50),
      ],
      'Film.B-GRP': [_rel(Tracker.tr4ker, 't2', 'Film.B-GRP', 200, 0)],
    })
      ..files['t1'] = torrentFile('Film.A-GRP', [(['a.mkv'], 100)]);
    // AstraTorrent : recherche littérale, le nom y est écrit avec des espaces.
    final astra = _Tracker(Tracker.astra, results: {
      'Film.A-GRP': [_rel(Tracker.astra, 'a1', 'Film.A-GRP', 100, 2)],
      'Film C-GRP': [_rel(Tracker.astra, 'a3', 'Film C-GRP', 300, 4)],
    });

    final transmission = _Transmission();
    final store = MemoryReviveStore();
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(transmission),
      trackersProvider.overrideWithValue(
          {Tracker.c411: c411, Tracker.tr4ker: tr4ker, Tracker.astra: astra}),
      reviveStoreProvider.overrideWithValue(store),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(_Torrents.new),
    ]);
    addTearDown(container.dispose);
    container.listen(reviveProvider, (_, _) {});
    final notifier = container.read(reviveProvider.notifier);

    await notifier.scan(
        deadOn: Tracker.c411,
        searchOn: [Tracker.c411, Tracker.tr4ker, Tracker.astra],
        categoryId: 7);
    expect(c411.requested, [1, 2], reason: 'arrêt à la première sortie seedée');
    var s = container.read(reviveProvider);
    final status = {for (final i in s.items) i.release.id: i.status};
    expect(status, {
      'c1': ReviveStatus.available,
      'c2': ReviveStatus.noSeeders,
      'c3': ReviveStatus.available, // seulement sur AstraTorrent
      'c4': ReviveStatus.present, // infohash déjà dans Transmission
    });
    final first = s.items.first;
    expect(first.candidate!.id, 't1', reason: 'la copie de même taille la plus seedée');
    expect(s.items[2].candidate!.tracker, Tracker.astra);
    expect(astra.queries, containsAllInOrder(['Film.C-GRP', 'Film C-GRP']));
    expect(tr4ker.queries.where((q) => q.contains(' ')), isEmpty,
        reason: 'pas de seconde recherche sur tr4ker');

    // Envoi : copie tr4ker téléchargée, .torrent C411 mis de côté.
    expect(await notifier.add(first), isNull);
    expect(transmission.added.single.$1, tr4ker.files['t1']);
    expect(container.read(reviveProvider).items.first.status, ReviveStatus.downloading);
    expect(store.load().keys, ['tr1']);

    // Téléchargement terminé : la sortie C411 s'ajoute dans le même dossier.
    (container.read(torrentsProvider.notifier) as _Torrents).emit(
        const TorrentsState(loaded: true, byId: {
          9: Torrent({'id': 9, 'hashString': 'TR1', 'percentDone': 1.0, 'status': 6,
              'downloadDir': '/data/films'}),
        }));
    await Future<void>.delayed(Duration.zero);
    expect(transmission.added, hasLength(2));
    final (metainfo, options) = transmission.added.last;
    expect(metainfo, c411.files['c1']);
    expect(options.downloadDir, '/data/films');
    expect(options.labels, [CrossSeedNotifier.label]);
    expect(container.read(reviveProvider).items.first.status, ReviveStatus.seeding);
    expect(store.load(), isEmpty);

    // Nombre limité : une seule page lue.
    c411.requested.clear();
    await notifier.scan(
        deadOn: Tracker.c411, searchOn: [Tracker.tr4ker], categoryId: 7, limit: 1);
    s = container.read(reviveProvider);
    expect(s.items.map((i) => i.release.id), ['c1']);
    expect(c411.requested, [1]);
  });

  test('dans l’autre sens : sorties tr4ker mortes, cherchées sur C411', () async {
    // Torznab ne trie pas par seeders : les pages arrivent par date, on ne
    // s'arrête pas à la première sortie seedée.
    final tr4ker = _Tracker(Tracker.tr4ker, pages: [
      [
        _rel(Tracker.tr4ker, 't1', 'Serie.A-GRP', 100, 0),
        _rel(Tracker.tr4ker, 't2', 'Serie.B-GRP', 200, 3),
      ],
      [_rel(Tracker.tr4ker, 't3', 'Serie.C-GRP', 300, 0)],
    ])
      ..files['t1'] = torrentFile('Serie.A-GRP', [(['a.mkv'], 100)]);
    final c411 = _Tracker(Tracker.c411, results: {
      'Serie.A-GRP': [_rel(Tracker.c411, 'c1', 'Serie.A-GRP', 100, 2)],
    })
      ..files['c1'] = torrentFile('Serie.A-GRP', [(['a.mkv'], 100)]);
    final astra = _Tracker(Tracker.astra);
    final transmission = _Transmission();
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(transmission),
      trackersProvider.overrideWithValue(
          {Tracker.c411: c411, Tracker.tr4ker: tr4ker, Tracker.astra: astra}),
      reviveStoreProvider.overrideWithValue(MemoryReviveStore()),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(_Torrents.new),
    ]);
    addTearDown(container.dispose);
    container.listen(reviveProvider, (_, _) {});
    final notifier = container.read(reviveProvider.notifier);

    await notifier.scan(
        deadOn: Tracker.tr4ker, searchOn: [Tracker.c411], categoryId: 7);
    final s = container.read(reviveProvider);
    expect(tr4ker.requested, [1, 2]);
    expect({for (final i in s.items) i.release.id: i.status}, {
      't1': ReviveStatus.available,
      't3': ReviveStatus.notFound,
    });
    expect(astra.queries, isEmpty, reason: 'AstraTorrent non coché');
    expect(c411.requested, isEmpty);

    // La copie vient de C411 ; le .torrent tr4ker attend la fin.
    expect(await notifier.add(s.items.first), isNull);
    expect(transmission.added.single.$1, c411.files['c1']);

    // Aucun tracker où chercher.
    await notifier.scan(deadOn: Tracker.tr4ker, searchOn: [Tracker.tr4ker]);
    expect(container.read(reviveProvider).error, contains('au moins un tracker'));
  });
}
