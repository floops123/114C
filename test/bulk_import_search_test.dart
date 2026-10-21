import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tracker qui renvoie une page de résultats sans dépendre du réseau. Les
/// `requests` accumulent les paramètres reçus pour que les assertions
/// vérifient ce que la page envoie.
class _FakeTracker implements TrackerApi {
  _FakeTracker(this.tracker, this.items);
  @override
  final Tracker tracker;
  final List<Release> items;
  final List<Map<String, Object?>> requests = [];

  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => const [ReleaseSort.seeders];
  @override
  Set<ReleaseSort> get serverSorts => const {ReleaseSort.seeders};
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
    requests.add({
      'page': page,
      'perPage': perPage,
      'query': query,
      'sort': sort.apiField,
      'ascending': ascending,
    });
    return ReleasePage(items, 1, 1, items.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

Release _r(Tracker t, String name, String sub,
        {int size = 1000, int seeders = 5, int leechers = 1}) =>
    Release(
      tracker: t,
      id: name,
      name: name,
      subcategory: sub,
      size: size,
      seeders: seeders,
      leechers: leechers,
      createdAt: DateTime(2026),
    );

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  test('search() avec un tracker qui renvoie des résultats : les items '
      'apparaissent dans l\'état', () async {
    final tr4ker = _FakeTracker(Tracker.tr4ker, [
      _r(Tracker.tr4ker, 'Matrix.1999.MULTI.1080p.BluRay-x264', 'Film'),
      _r(Tracker.tr4ker, 'Matrix.Reloaded.2003.MULTI.1080p', 'Film'),
    ]);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      trackersProvider.overrideWithValue({Tracker.tr4ker: tr4ker}),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(bulkImportProvider.notifier);

    expect(container.read(bulkImportProvider).items, isEmpty);
    notifier.search();
    // Laisse le microtask et l'appel HTTP se résoudre.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final state = container.read(bulkImportProvider);
    expect(state.error, isNull);
    expect(state.items, hasLength(2),
        reason: 'les deux sorties du faux tracker doivent apparaître');
    expect(state.items.map((i) => i.release.name),
        containsAll(['Matrix.1999.MULTI.1080p.BluRay-x264', 'Matrix.Reloaded.2003.MULTI.1080p']));
    // La requête a bien été envoyée avec les bons paramètres.
    expect(tr4ker.requests, hasLength(1));
    expect(tr4ker.requests.single['query'], '');
    expect(tr4ker.requests.single['sort'], 'seeders');
  });

  test('search() avec un nom : le query est envoyé', () async {
    final tr4ker = _FakeTracker(Tracker.tr4ker, [
      _r(Tracker.tr4ker, 'Matrix.1999.MULTI.1080p', 'Film'),
    ]);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      trackersProvider.overrideWithValue({Tracker.tr4ker: tr4ker}),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.update(const BulkCriteria(name: 'Matrix'));
    notifier.search();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(tr4ker.requests.single['query'], 'Matrix');
  });

  test('search() sans tracker configuré : état vide, pas d\'erreur', () async {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      trackersProvider.overrideWithValue(const {}),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.search();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final state = container.read(bulkImportProvider);
    expect(state.items, isEmpty);
    expect(state.error, isNull);
    // Pas de spinner, pas de page de résultats.
    expect(state.loading, isFalse);
  });
}