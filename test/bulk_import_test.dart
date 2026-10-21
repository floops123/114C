import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:flutter_test/flutter_test.dart';

Release _r({
  Tracker tracker = Tracker.c411,
  int size = 1024,
  int seeders = 0,
  int leechers = 0,
  String subcategory = 'Film',
  String? name,
  String? mediaKind,
}) =>
    Release(
      tracker: tracker,
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

    test('catégorie : laissée au tracker, pas refiltrée ici', () {
      const c = BulkCriteria(categories: {(category: 1, subcategory: 6)});
      expect(c.accepts(_r(subcategory: 'Série')), isTrue);
      expect(c.accepts(_r(subcategory: '')), isTrue);
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

    test('combinaison : tous les filtres ensemble', () {
      const c = BulkCriteria(
        sizeMin: 1024,
        sizeMax: 4096,
        seedersMin: 1,
        leechersMax: 5,
      );
      expect(c.accepts(_r(size: 2048, seeders: 3, leechers: 2)), isTrue);
      // Trop gros.
      expect(c.accepts(_r(size: 8192, seeders: 3, leechers: 2)), isFalse);
      // Pas de seeder.
      expect(c.accepts(_r(size: 2048, seeders: 0, leechers: 2)), isFalse);
    });
  });

  group('BulkCriteria.hasFilters', () {
    test('tout vide : false', () {
      const c = BulkCriteria();
      expect(c.hasFilters, isFalse);
    });

    test('le tracker choisi n’est pas un filtre', () {
      const c = BulkCriteria(tracker: Tracker.c411);
      expect(c.hasFilters, isFalse);
    });

    test('catégories non vide : true', () {
      const c = BulkCriteria(categories: {(category: 1, subcategory: null)});
      expect(c.hasFilters, isTrue);
    });
  });
}