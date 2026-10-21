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
    // Sous-catégorie 6 : les numéros pairs, 7 : les impairs.
    final inCategory = switch (subcategoryId) {
      6 => all.where((r) => int.parse(r.id).isEven).toList(),
      7 => all.where((r) => int.parse(r.id).isOdd).toList(),
      _ => all,
    };
    final ordered = sortsBySize && sort == ReleaseSort.size && ascending
        ? inCategory
        : inCategory.reversed.toList();
    final items = ordered.skip((page - 1) * perPage).take(perPage).toList();
    return ReleasePage(items, page, (ordered.length / perPage).ceil(),
        ordered.length);
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

  test('deux catégories cochées : chacune parcourue par taille, résultats '
      'fusionnés', () async {
    final c411 = _Catalog(Tracker.c411);
    final container = _container({Tracker.c411: c411});
    addTearDown(container.dispose);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.update(const BulkCriteria(
      sizeMax: 20 * _mo,
      categories: {(category: 1, subcategory: 6), (category: 1, subcategory: 7)},
    ));
    notifier.search();
    await _settle();

    final state = container.read(bulkImportProvider);
    expect(c411.params.map((p) => p.sub), unorderedEquals([6, 7]));
    expect([for (final i in state.items) i.release.size ~/ _mo],
        [for (var s = 1; s <= 20; s++) s]);
    expect(state.hasMore, isFalse, reason: 'les deux ont dépassé 20 Mo');
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

  testWidgets('écran : un tracker à la fois, avec ses catégories',
      (tester) async {
    final c411 = _Catalog(Tracker.c411, cats: const [
      Category(1, 'Films & Vidéos', [Subcategory(6, 'Film')]),
    ]);
    final torznab = _Catalog(Tracker.tr4ker, sortsBySize: false, cats: const [
      Category(2000, 'Movies', [Subcategory(2040, 'Movies/HD')]),
    ]);
    final container =
        _container({Tracker.c411: c411, Tracker.tr4ker: torznab});
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
    await tester.runAsync(_settle);
    await tester.pump();

    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Movies/HD'), findsNothing);
    expect(find.text('Tous les trackers'), findsNothing);

    await tester.tap(find.text('Film'));
    await tester.pump();
    expect(container.read(bulkImportProvider).criteria.categories,
        {(category: 1, subcategory: 6)});

    await tester.tap(find.text(Tracker.tr4ker.label));
    await tester.runAsync(_settle);
    await tester.pump();
    expect(find.text('Movies/HD'), findsOneWidget);
    expect(find.text('Film'), findsNothing);
    expect(container.read(bulkImportProvider).criteria.categories, isEmpty);

    await tester.tap(find.text('Movies/HD'));
    await tester.pump();
    await tester.tap(find.text('Rechercher'));
    await tester.runAsync(_settle);
    await tester.pump();
    expect(torznab.params.first.cat, 2000);
    expect(torznab.params.first.sub, 2040);
    expect(c411.params, isEmpty);
  });
}
