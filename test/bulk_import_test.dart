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

    test('trackers : seul celui coché passe', () {
      const c = BulkCriteria(trackers: {Tracker.c411});
      expect(c.accepts(_r(tracker: Tracker.c411)), isTrue);
      expect(c.accepts(_r(tracker: Tracker.tr4ker)), isFalse);
    });

    test('trackers : ensemble vide = pas de filtre', () {
      const c = BulkCriteria(trackers: {});
      expect(c.accepts(_r(tracker: Tracker.c411)), isTrue);
      expect(c.accepts(_r(tracker: Tracker.tr4ker)), isTrue);
    });

    test('catégories : ensemble insensible à la casse', () {
      const c = BulkCriteria(categories: {'film'});
      expect(c.accepts(_r(subcategory: 'Film')), isTrue);
      expect(c.accepts(_r(subcategory: 'FILM')), isTrue);
      expect(c.accepts(_r(subcategory: 'Série')), isFalse);
    });

    test('catégories : ensemble vide = pas de filtre', () {
      const c = BulkCriteria(categories: {});
      expect(c.accepts(_r(subcategory: 'Film')), isTrue);
      expect(c.accepts(_r(subcategory: '')), isTrue);
    });

    test('catégories : sortie sans sous-catégorie n\'est pas acceptée', () {
      const c = BulkCriteria(categories: {'Film'});
      expect(c.accepts(_r(subcategory: '')), isFalse);
    });

    test('catégories : multi-sélection', () {
      const c = BulkCriteria(categories: {'Film', 'Série'});
      expect(c.accepts(_r(subcategory: 'Film')), isTrue);
      expect(c.accepts(_r(subcategory: 'Série')), isTrue);
      expect(c.accepts(_r(subcategory: 'Animation')), isFalse);
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
        trackers: {Tracker.c411},
        categories: {'Film'},
        sizeMin: 1024,
        sizeMax: 4096,
        seedersMin: 1,
        leechersMax: 5,
      );
      final r = _r(size: 2048, seeders: 3, leechers: 2, subcategory: 'Film');
      expect(c.accepts(r), isTrue);
      // Mauvais tracker.
      expect(c.accepts(_r(
              tracker: Tracker.tr4ker,
              size: 2048,
              seeders: 3,
              leechers: 2,
              subcategory: 'Film')),
          isFalse);
      // Mauvaise catégorie.
      expect(c.accepts(_r(size: 2048, seeders: 3, leechers: 2, subcategory: 'Série')),
          isFalse);
      // Trop gros.
      expect(c.accepts(_r(
              size: 8192, seeders: 3, leechers: 2, subcategory: 'Film')),
          isFalse);
    });
  });

  group('BulkCriteria.hasFilters', () {
    test('tout vide : false', () {
      const c = BulkCriteria();
      expect(c.hasFilters, isFalse);
    });

    test('trackers non vide : true', () {
      const c = BulkCriteria(trackers: {Tracker.c411});
      expect(c.hasFilters, isTrue);
    });

    test('catégories non vide : true', () {
      const c = BulkCriteria(categories: {'Film'});
      expect(c.hasFilters, isTrue);
    });
  });
}