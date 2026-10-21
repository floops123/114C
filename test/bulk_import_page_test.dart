import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/catalog.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:c411_remote/ui/bulk_import_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _C411 implements TrackerApi {
  _C411(this.categories_);
  final List<Category> categories_;
  @override
  Tracker get tracker => Tracker.c411;
  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => const [ReleaseSort.seeders];
  @override
  Set<ReleaseSort> get serverSorts => const {ReleaseSort.seeders};
  @override
  Future<List<Category>> categories() async => categories_;
  @override
  Future<ReleasePage> releases(
          {int page = 1,
          int perPage = 50,
          int? categoryId,
          int? subcategoryId,
          String query = '',
          ReleaseSort sort = ReleaseSort.date,
          bool ascending = false}) async =>
      ReleasePage(const [], 1, 1, 0);
  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

class _SettingsEmpty extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  testWidgets('ouvrir la page ne doit pas crasher (lecture de state dans build)',
      (tester) async {
    final store = MemoryMediaLibraryStore();
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_SettingsEmpty.new),
      trackersProvider.overrideWithValue({
        Tracker.c411: _C411([
          Category(1, 'Films & Vidéos', [
            Subcategory(1, 'Film'),
            Subcategory(2, 'Série'),
          ]),
          Category(2, 'Audio', [Subcategory(3, 'FLAC')]),
        ]),
      }),
      tmdbMatchStoreProvider.overrideWithValue(MemoryTmdbMatchStore()),
      mediaLibraryStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const BulkImportPage(),
      ),
    ));
    // Avant le fix, `state` lu dans `build` levait une StateError Riverpod.
    await tester.pump();
    expect(find.text('Import en masse'), findsOneWidget);
    // Les catégories sont chargées en arrière-plan.
    await tester.pump(const Duration(milliseconds: 50));
    // Repliées : les catégories parentes seulement.
    expect(find.text('Films & Vidéos'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Film'), findsNothing);
    // Peu de catégories : pas de champ de filtre ; on déplie à la main.
    expect(find.widgetWithText(TextField, 'Filtrer les catégories'),
        findsNothing);
    await tester.tap(find.text('Audio'));
    await tester.pump();
    expect(find.text('FLAC'), findsOneWidget);
  });
}