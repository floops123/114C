import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:flutter_test/flutter_test.dart';

Release _r({
  int size = 1024,
  int seeders = 0,
  int leechers = 0,
  String subcategory = 'Film',
  String? name,
  String? mediaKind,
}) =>
    Release(
      tracker: Tracker.c411,
      id: '1',
      name: name ?? 'A.1080p.mkv',
      size: size,
      seeders: seeders,
      leechers: leechers,
      subcategory: subcategory,
      createdAt: DateTime(2026),
      mediaKind: mediaKind,
    );

void main() {
  group('BulkCriteria.accepts', () {
    test('tout ouvert : accepte tout', () {
      const c = BulkCriteria();
      expect(c.accepts(_r()), isTrue);
      expect(c.hasFilters, isFalse);
    });

    test('taille : min et max', () {
      const c = BulkCriteria(sizeMin: 1000, sizeMax: 2000);
      expect(c.accepts(_r(size: 500)), isFalse);
      expect(c.accepts(_r(size: 1000)), isTrue);
      expect(c.accepts(_r(size: 1500)), isTrue);
      expect(c.accepts(_r(size: 2000)), isTrue);
      expect(c.accepts(_r(size: 3000)), isFalse);
    });

    test('seeders : min et max', () {
      const c = BulkCriteria(seedersMin: 3, seedersMax: 10);
      expect(c.accepts(_r(seeders: 2)), isFalse);
      expect(c.accepts(_r(seeders: 3)), isTrue);
      expect(c.accepts(_r(seeders: 10)), isTrue);
      expect(c.accepts(_r(seeders: 11)), isFalse);
    });

    test('leechers : min et max', () {
      const c = BulkCriteria(leechersMin: 1, leechersMax: 5);
      expect(c.accepts(_r(leechers: 0)), isFalse);
      expect(c.accepts(_r(leechers: 3)), isTrue);
      expect(c.accepts(_r(leechers: 6)), isFalse);
    });

    test('catégorie : insensible à la casse', () {
      const c = BulkCriteria(category: 'film');
      expect(c.accepts(_r(subcategory: 'Film')), isTrue);
      expect(c.accepts(_r(subcategory: 'FILM')), isTrue);
      expect(c.accepts(_r(subcategory: 'Série')), isFalse);
    });

    test('catégorie : sortie sans sous-catégorie n\'est pas acceptée', () {
      const c = BulkCriteria(category: 'Film');
      expect(c.accepts(_r(subcategory: '')), isFalse);
    });

    test('combinaison : tous les filtres ensemble', () {
      const c = BulkCriteria(
        sizeMin: 1024,
        sizeMax: 4096,
        seedersMin: 1,
        leechersMax: 5,
        category: 'Film',
      );
      final r = _r(size: 2048, seeders: 3, leechers: 2, subcategory: 'Film');
      expect(c.accepts(r), isTrue);
      // Sortie trop grosse.
      expect(c.accepts(_r(
          size: 8192, seeders: 3, leechers: 2, subcategory: 'Film')), isFalse);
    });
  });

  group('BulkCriteria.copyWith', () {
    test('clearCategory remet à null', () {
      const c = BulkCriteria(category: 'Film');
      expect(c.copyWith(clearCategory: true).category, isNull);
      // Sans clear, on garde l'ancienne.
      expect(c.copyWith(sizeMin: 100).category, 'Film');
    });

    test('copyWith remplace un champ défini', () {
      const c = BulkCriteria(sizeMin: 100);
      expect(c.copyWith(sizeMin: 200).sizeMin, 200);
    });

    test('copyWith préserve un champ non touché', () {
      const c = BulkCriteria(sizeMin: 100, sizeMax: 200);
      expect(c.copyWith(seedersMin: 5).sizeMin, 100);
      expect(c.copyWith(seedersMin: 5).sizeMax, 200);
    });
  });
}