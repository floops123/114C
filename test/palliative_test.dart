import 'dart:typed_data';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/cross_seed.dart';
import 'package:c411_remote/state/palliative.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cross_seed_test.dart' show torrentFile;

// --- Doublures (versions publiques pour réutilisation depuis d'autres
// fichiers de test si besoin).

class FakeTransmission extends TransmissionClient {
  FakeTransmission() : super(url: 'http://x');
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

class FakeTracker implements TrackerApi {
  FakeTracker(this.tracker, {this.pages = const [], this.results = const {}});
  @override
  final Tracker tracker;
  final List<List<Release>> pages;
  final Map<String, List<Release>> results;
  final files = <String, Uint8List>{};
  final requested = <int>[];
  final queries = <String>[];

  @override
  void close() {}

  @override
  List<ReleaseSort> get sorts => const [];

  @override
  Set<ReleaseSort> get serverSorts =>
      tracker == Tracker.c411 ? const {ReleaseSort.seeders} : const {};

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
    if (query.isNotEmpty) {
      queries.add(query);
      final r = results[query] ?? const [];
      return ReleasePage(r, 1, 1, r.length);
    }
    return ReleasePage(pages[page - 1], page, pages.length, 0);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => files[release.id]!;
}

Release _rel(Tracker t, String id, String name, int size, int seeders) => Release(
      tracker: t,
      id: id,
      name: name,
      size: size,
      seeders: seeders,
      infoHash: 'h$id',
      createdAt: DateTime(2026),
    );

class FakeTorrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true, hashes: {});
  @override
  Future<void> refresh({bool full = false}) async {}
  void emit(TorrentsState s) => state = s;
}

/// C411 site : renvoie une liste paginée de sorties palliatives.
class FakeC411Site extends C411SiteApi {
  FakeC411Site({required this.pages, this.totalPages = 1}) : super('fake-cookie');
  final List<List<Release>> pages;
  final int totalPages;
  int pageRequested = 0;

  @override
  Future<ReleasePage> palliative(
      {String age = 'recent', int page = 1, int perPage = 25}) async {
    pageRequested = page;
    final List<Release> items =
        page <= pages.length ? pages[page - 1] : const <Release>[];
    return ReleasePage(items, page, totalPages, totalPages * items.length);
  }
}

void main() {
  test('liste palliative C411, candidates par tracker, cross-seed', () async {
    // C411 site : trois sorties palliatives.
    final site = FakeC411Site(pages: [
      [
        _rel(Tracker.c411, 'c1', 'Film.A-GRP', 100, 0),
        _rel(Tracker.c411, 'c2', 'Film.B-GRP', 200, 0),
        _rel(Tracker.c411, 'c3', 'Film.C-GRP', 300, 0),
      ],
    ], totalPages: 1);
    // Le client C411 de l'API « publique » partage les .torrent.
    final c411 = FakeTracker(Tracker.c411)
      ..files['c1'] = torrentFile('Film.A-GRP', [(['a.mkv'], 100)]);

    // tr4ker : deux des trois sont trouvés.
    final tr4ker = FakeTracker(Tracker.tr4ker, results: {
      'Film.A-GRP': [_rel(Tracker.tr4ker, 't1', 'Film.A-GRP', 100, 5)],
      'Film.C-GRP': [_rel(Tracker.tr4ker, 't3', 'Film.C-GRP', 300, 0)],
    })
      ..files['t1'] = torrentFile('Film.A-GRP', [(['a.mkv'], 100)]);
    // AstraTorrent : le deuxième est trouvé (variante avec espaces).
    final astra = FakeTracker(Tracker.astra, results: {
      'Film B-GRP': [_rel(Tracker.astra, 'a2', 'Film B-GRP', 200, 2)],
    });

    final transmission = FakeTransmission();
    final store = MemoryPalliativeStore();
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(transmission),
      trackersProvider.overrideWithValue({
        Tracker.c411: c411,
        Tracker.tr4ker: tr4ker,
        Tracker.astra: astra,
      }),
      c411SiteApiProvider.overrideWithValue(site),
      palliativeStoreProvider.overrideWithValue(store),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(FakeTorrents.new),
    ]);
    addTearDown(container.dispose);
    container.listen(palliativeProvider, (_, _) {});
    final notifier = container.read(palliativeProvider.notifier);

    await notifier.scan();
    final s = container.read(palliativeProvider);
    expect(site.pageRequested, 1);
    expect({for (final i in s.items) i.release.id: i.status}, {
      'c1': PalliativeStatus.available,
      'c2': PalliativeStatus.available, // AstraTorrent : 2 seeders
      'c3': PalliativeStatus.noSeeders, // trouvé mais 0 seeder
    });
    final first = s.items.first;
    expect(first.best!.id, 't1');
    expect(first.best!.tracker, Tracker.tr4ker);
    expect(first.candidates.length, 1);

    // Envoi : copie tr4ker téléchargée, .torrent C411 mis de côté pour le
    // cross-seed.
    expect(await notifier.add(first), isNull);
    expect(transmission.added.single.$1, tr4ker.files['t1']);
    expect(container.read(palliativeProvider).items.first.status,
        PalliativeStatus.downloading);
    expect(store.load().keys.single, 'tr1');
    expect(store.load().values.single.name, 'Film.A-GRP');

    // Téléchargement terminé : la sortie C411 s'ajoute dans le même dossier.
    (container.read(torrentsProvider.notifier) as FakeTorrents).emit(
        const TorrentsState(loaded: true, byId: {
      9: Torrent({
        'id': 9,
        'hashString': 'TR1',
        'percentDone': 1.0,
        'status': 6,
        'downloadDir': '/data/films'
      }),
    }));
    await Future<void>.delayed(Duration.zero);
    expect(transmission.added, hasLength(2));
    final (metainfo, options) = transmission.added.last;
    expect(metainfo, c411.files['c1']);
    expect(options.downloadDir, '/data/films');
    expect(options.labels, [CrossSeedNotifier.label]);
    expect(container.read(palliativeProvider).items.first.status,
        PalliativeStatus.seeding);
    expect(store.load(), isEmpty);
  });

  test('cookie absent : erreur explicite', () async {
    final container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue({
        Tracker.c411: FakeTracker(Tracker.c411),
        Tracker.tr4ker: FakeTracker(Tracker.tr4ker),
      }),
      c411SiteApiProvider.overrideWithValue(null),
      palliativeStoreProvider.overrideWithValue(MemoryPalliativeStore()),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(FakeTorrents.new),
    ]);
    addTearDown(container.dispose);
    container.listen(palliativeProvider, (_, _) {});
    final notifier = container.read(palliativeProvider.notifier);
    await notifier.scan();
    expect(container.read(palliativeProvider).error, contains('cookie'));
  });

  test('aucun tracker non-C411 : erreur', () async {
    final site = FakeC411Site(pages: [
      [_rel(Tracker.c411, 'c1', 'Film.A-GRP', 100, 0)],
    ]);
    final container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue({Tracker.c411: FakeTracker(Tracker.c411)}),
      c411SiteApiProvider.overrideWithValue(site),
      palliativeStoreProvider.overrideWithValue(MemoryPalliativeStore()),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(FakeTorrents.new),
    ]);
    addTearDown(container.dispose);
    container.listen(palliativeProvider, (_, _) {});
    final notifier = container.read(palliativeProvider.notifier);
    await notifier.scan();
    expect(container.read(palliativeProvider).error, contains('tracker'));
  });
}