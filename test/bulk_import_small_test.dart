import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/bulk_import_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mo = 1000000;

/// Catalogue de 1 000 sorties de 1 à 1 000 Mo. Avec [sortsBySize], le tracker
/// trie lui-même par taille (comme C411) ; sinon il ne renvoie que les plus
/// récentes (comme un indexeur Torznab), ici les plus grosses d'abord.
class _Catalog implements TrackerApi {
  _Catalog(this.tracker, {this.sortsBySize = true, this.cats = const []});
  @override
  final Tracker tracker;
  final bool sortsBySize;
  final List<Category> cats;
  final pages = <int>[];
  final params = <({ReleaseSort sort, bool ascending, int? cat, int? sub})>[];

  late final all = [
    for (var i = 1; i <= 1000; i++)
      Release(
        tracker: tracker,
        id: '$i',
        name: 'R$i',
        infoHash: 'h$i',
        size: i * _mo,
        seeders: i % 7,
        createdAt: DateTime(2026).add(Duration(minutes: i)),
      ),
  ];

  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => ReleaseSort.values;
  @override
  Set<ReleaseSort> get serverSorts =>
      sortsBySize ? ReleaseSort.values.toSet() : const {};
  @override
  Future<List<Category>> categories() async => cats;
  @override
  Future<ReleasePage> releases(
      {int page = 1,
      int perPage = 50,
      int? categoryId,
      int? subcategoryId,
      String query = '',
      ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    pages.add(page);
    params.add((
      sort: sort,
      ascending: ascending,
      cat: categoryId,
      sub: subcategoryId,
    ));
    final ordered = sortsBySize && sort == ReleaseSort.size && ascending
        ? all
        : all.reversed.toList();
    final items = ordered.skip((page - 1) * perPage).take(perPage).toList();
    return ReleasePage(
        items, page, (all.length / perPage).ceil(), all.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(hashes: {'h3'});
}

Future<void> _settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container(Map<Tracker, TrackerApi> trackers) {
  final c = ProviderContainer(overrides: [
    trackersProvider.overrideWithValue(trackers),
    torrentsProvider.overrideWith(_Torrents.new),
  ]);
  c.listen(bulkImportProvider, (_, _) {});
  return c;
}

void main() {
  test('plus petits d’abord : tri demandé au tracker, arrêt à la taille max',
      () async {
    final c411 = _Catalog(Tracker.c411);
    final container = _container({Tracker.c411: c411});
    addTearDown(container.dispose);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.update(const BulkCriteria(sizeMax: 120 * _mo));
    notifier.search();
    await _settle();

    var state = container.read(bulkImportProvider);
    expect(c411.params.first.sort, ReleaseSort.size);
    expect(c411.params.first.ascending, isTrue);
    // Une page suffit à atteindre l'objectif de résultats.
    expect(c411.pages, [1]);
    expect(state.items.first.release.size, 1 * _mo);
    expect(state.hasMore, isTrue);
    expect(state.loading, isFalse);
    expect(state.scanned, 50);

    notifier.loadMore();
    await _settle();
    notifier.loadMore();
    await _settle();
    state = container.read(bulkImportProvider);
    // Page 3 (101 à 150 Mo) dépasse la taille max : on s'arrête là.
    expect(c411.pages, [1, 2, 3]);
    expect(state.items, hasLength(120));
    expect(state.hasMore, isFalse);
    final sizes = [for (final i in state.items) i.release.size];
    expect(sizes, [...sizes]..sort(), reason: 'affichés du plus petit');
  });

  test('taille min : la bonne page est trouvée par dichotomie', () async {
    final c411 = _Catalog(Tracker.c411);
    final container = _container({Tracker.c411: c411});
    addTearDown(container.dispose);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.update(
        const BulkCriteria(sizeMin: 700 * _mo, sizeMax: 720 * _mo));
    notifier.search();
    await _settle();

    final state = container.read(bulkImportProvider);
    // 700 Mo est la dernière sortie de la page 14.
    expect(c411.pages, contains(14));
    expect(c411.pages.length, lessThan(10),
        reason: 'pas les 14 pages une à une');
    expect([for (final i in state.items) i.release.size ~/ _mo],
        [for (var s = 700; s <= 720; s++) s]);
    expect(state.hasMore, isFalse);
  });

  test('tracker sans tri par taille : les pages s’enchaînent seules '
      'jusqu’à trouver assez de résultats', () async {
    final torznab = _Catalog(Tracker.tr4ker, sortsBySize: false);
    final container = _container({Tracker.tr4ker: torznab});
    addTearDown(container.dispose);
    final notifier = container.read(bulkImportProvider.notifier);
    // Les plus récentes sont les plus grosses : rien avant la page 17.
    notifier.update(const BulkCriteria(sizeMax: 200 * _mo));
    notifier.search();
    await _settle();

    final state = container.read(bulkImportProvider);
    expect(torznab.params.first.sort, ReleaseSort.date);
    // Plafond de tours par recherche, puis « Encore ».
    expect(torznab.pages, hasLength(BulkImportNotifier.maxPages));
    expect(state.items, isEmpty);
    expect(state.scanned, 500);
    expect(state.hasMore, isTrue);
  });

  test('déjà dans Transmission : signalée et décochée', () async {
    final c411 = _Catalog(Tracker.c411);
    final container = _container({Tracker.c411: c411});
    addTearDown(container.dispose);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.update(const BulkCriteria(sizeMax: 5 * _mo));
    notifier.search();
    await _settle();

    final state = container.read(bulkImportProvider);
    final third = state.items.firstWhere((i) => i.release.id == '3');
    expect(third.present, isTrue);
    expect(third.selected, isFalse);
    expect(state.selected, hasLength(4));
    expect(state.selectedSize, (1 + 2 + 4 + 5) * _mo);
  });

  test('stopper puis « Encore » reprend', () async {
    final c411 = _Catalog(Tracker.c411);
    final container = _container({Tracker.c411: c411});
    addTearDown(container.dispose);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.search();
    notifier.stop();
    await _settle();
    expect(container.read(bulkImportProvider).items, isEmpty);
    expect(container.read(bulkImportProvider).hasMore, isTrue);
    notifier.loadMore();
    await _settle();
    expect(container.read(bulkImportProvider).items, hasLength(50));
  });

  group('catégorie transmise au tracker', () {
    const cats = [
      Category(1, 'Films & Vidéos', [Subcategory(6, 'Film'), Subcategory(7, 'Série')]),
      Category(2, 'Ebook', [Subcategory(14, 'Livres')]),
    ];

    test('une seule correspondance : transmise', () {
      expect(BulkImportNotifier.serverCategory(cats, {'film'}),
          (category: 1, subcategory: 6));
      expect(BulkImportNotifier.serverCategory(cats, {'Ebook'}),
          (category: 2, subcategory: null));
    });

    test('dans la requête de recherche', () async {
      final c411 = _Catalog(Tracker.c411, cats: cats);
      final container = _container({Tracker.c411: c411});
      addTearDown(container.dispose);
      await _settle(); // catégories chargées à l'ouverture
      final notifier = container.read(bulkImportProvider.notifier);
      notifier.update(const BulkCriteria(categories: {'Film'}));
      notifier.search();
      await _settle();
      expect(c411.params.first.cat, 1);
      expect(c411.params.first.sub, 6);
    });

    test('plusieurs, aucune, ou catégories inconnues : filtre local', () {
      const none = (category: null, subcategory: null);
      expect(BulkImportNotifier.serverCategory(cats, {'Film', 'Série'}), none);
      expect(BulkImportNotifier.serverCategory(cats, {'Movies/HD'}), none);
      expect(BulkImportNotifier.serverCategory(cats, const {}), none);
      expect(BulkImportNotifier.serverCategory(null, {'Film'}), none);
    });
  });

  testWidgets('écran : raccourci de taille, recherche, résultats', (tester) async {
    final c411 = _Catalog(Tracker.c411);
    final container = _container({Tracker.c411: c411});
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const BulkImportPage(),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('≤ 50 Mo'));
    await tester.pump();
    expect(container.read(bulkImportProvider).criteria.sizeMax, 50 << 20);

    await tester.tap(find.text('Rechercher'));
    await tester.runAsync(_settle);
    await tester.pump();

    // Une page suffit (objectif de résultats atteint) ; R3 déjà présente.
    expect(find.textContaining('50 résultats sur 50 examinés'), findsOneWidget);
    expect(find.text('DANS TRANSMISSION'), findsOneWidget);
    expect(find.textContaining('Envoyer à Transmission (49 ·'), findsOneWidget);
    expect(c411.pages, [1]);
    // La page 2 (51 et 52 Mo) reste à prendre.
    expect(find.text('Encore'), findsOneWidget);
  });
}
